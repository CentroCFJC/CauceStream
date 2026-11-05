"""Device management and heartbeat endpoints.

Queries require `devices.view`; registration and autoconfig require
`devices.manage`. The heartbeat is the public device-protocol endpoint:
it carries no user authentication (clients are devices, not users) and
can only update previously registered devices, never create them.
Unknown devices are accepted as pending discoveries only while the
autoconfig mode is enabled (they are still never auto-registered).

The WebSocket playback endpoint shares the device-protocol nature: no
user credentials (the same deferred device-security applies), only
registered devices, and it never replaces the heartbeat - liveness and
`current_media` still come exclusively from heartbeats.
"""

import asyncio
import json
import logging

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    WebSocket,
    status,
)
from fastapi.responses import JSONResponse
from starlette.websockets import WebSocketDisconnect

from app.api.deps import (
    get_assignment_service,
    get_device_service,
    get_power_controller_registry,
    require_permission,
)
from app.core.config import get_settings
from app.core.database import AsyncSessionLocal
from app.core.device_auth import require_device_key, verify_device_key
from app.core.exceptions import NotFoundError
from app.power.base import PowerControllerRegistry
from app.power.websocket import WebSocketPowerController
from app.core.ws import (
    WSC_INTERNAL_ERROR,
    WSC_MESSAGE_TOO_LARGE,
    WSC_POLICY_VIOLATION,
    connection_manager,
)
from app.models.device import Device
from app.models.user import User
from app.schemas.assignment import AssignmentCreate, AssignmentSetResult
from app.schemas.device import (
    AutoconfigStatus,
    AutoconfigToggle,
    DeviceEventRead,
    DevicePowerAction,
    DevicePowerResult,
    DeviceRead,
    DeviceRegister,
    DeviceUpdate,
    HeartbeatPayload,
    HeartbeatResponse,
    PendingDeviceList,
)
from app.schemas.playback import PowerAck, PowerClientError
from app.services.assignment_service import AssignmentService
from app.services.device_service import DeviceService, PendingHeartbeat
from app.services.playback_service import (
    MAX_INBOUND_MESSAGE_BYTES,
    build_sync_message,
    parse_client_message,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/devices", tags=["devices"])


def _device_read(device: Device) -> DeviceRead:
    """DeviceRead enriched with the live WebSocket channel state.

    In-memory lookup only (no DB access): the admin UI shows whether the
    device can receive playback commands in real time.
    """
    read = DeviceRead.model_validate(device)
    read.ws_connected = connection_manager.has(device.device_uid)
    return read


@router.post(
    "",
    response_model=DeviceRead,
    status_code=status.HTTP_201_CREATED,
    summary="Register a device",
)
async def register_device(
    payload: DeviceRegister,
    actor: User = Depends(require_permission("devices.manage")),
    service: DeviceService = Depends(get_device_service),
):
    """Register a device. It starts offline until its first heartbeat."""
    return await service.register(payload)


@router.get(
    "",
    response_model=list[DeviceRead],
    summary="List devices",
)
async def list_devices(
    actor: User = Depends(require_permission("devices.view")),
    service: DeviceService = Depends(get_device_service),
):
    return [_device_read(d) for d in await service.list_devices()]


@router.get(
    "/{device_uid}",
    response_model=DeviceRead,
    summary="Get a device by device_uid",
)
async def get_device(
    device_uid: str,
    actor: User = Depends(require_permission("devices.view")),
    service: DeviceService = Depends(get_device_service),
):
    return _device_read(await service.get_device(device_uid))


@router.delete(
    "/{device_uid}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a device",
)
async def delete_device(
    device_uid: str,
    actor: User = Depends(require_permission("devices.manage")),
    service: DeviceService = Depends(get_device_service),
):
    """Delete a registered device and its whole change history. Pure
    deregistration: it is never re-created automatically; a later
    heartbeat of its uid behaves as an unknown device (404, or a new
    discovery if the autoconfig mode is enabled)."""
    await service.delete_device(device_uid)


@router.patch(
    "/{device_uid}",
    response_model=DeviceRead,
    summary="Update device registration data",
)
async def update_device(
    device_uid: str,
    payload: DeviceUpdate,
    actor: User = Depends(require_permission("devices.manage")),
    service: DeviceService = Depends(get_device_service),
):
    """Partial update of name/type/IP/MAC. `type` is not cosmetic: it
    selects the server-side power controller used by
    POST /api/devices/{uid}/power (e.g. "google_tv"/"android_tv" -> ADB
    from the server; anything else -> WebSocket fallback)."""
    device = await service.update(device_uid, payload)
    return _device_read(device)


@router.get(
    "/{device_uid}/events",
    response_model=list[DeviceEventRead],
    summary="Device change history",
)
async def list_device_events(
    device_uid: str,
    actor: User = Depends(require_permission("devices.view")),
    service: DeviceService = Depends(get_device_service),
):
    """Relevant changes only (registration, status, operational state,
    media, IP, port). Identical consecutive heartbeats generate no
    history; device-specific payload metrics are not evented."""
    return await service.list_events(device_uid)


@router.post(
    "/autoconfig",
    response_model=AutoconfigStatus,
    status_code=status.HTTP_200_OK,
    summary="Toggle device autoconfig mode",
)
async def set_autoconfig(
    payload: AutoconfigToggle,
    actor: User = Depends(require_permission("devices.manage")),
    service: DeviceService = Depends(get_device_service),
):
    """Enable/disable autoconfig discovery (default and after restart:
    disabled). While enabled, heartbeats from unregistered devices are
    kept as pending discoveries; no device is ever registered
    automatically. Disabling clears the pending list."""
    enabled = await service.set_autoconfig_enabled(payload.enabled)
    return AutoconfigStatus(enabled=enabled)


@router.get(
    "/autoconfig/pending",
    response_model=PendingDeviceList,
    summary="Discovered devices awaiting registration",
)
async def list_pending_devices(
    actor: User = Depends(require_permission("devices.manage")),
    service: DeviceService = Depends(get_device_service),
):
    """Unregistered devices that sent a heartbeat within the last
    AUTOCONFIG_PENDING_TTL_SECONDS (30 s). Registered devices and
    duplicates are never included; `payload` is not exposed."""
    return PendingDeviceList(devices=await service.list_pending_devices())


@router.post(
    "/{device_uid}/heartbeat",
    response_model=HeartbeatResponse,
    status_code=status.HTTP_200_OK,
    summary="Receive a device heartbeat",
)
async def receive_heartbeat(
    device_uid: str,
    payload: HeartbeatPayload,
    _device_auth: None = Depends(require_device_key),
    service: DeviceService = Depends(get_device_service),
):
    """Device protocol endpoint (shared device key via the X-Device-Key
    header when CAUCE_DEVICE_SECRET is configured). General fields
    (address, operational state) are transversal; device-specific
    attributes - including the
    current media (its numeric id from the library) - go in the
    optional `payload` object. The server
    derives connectivity and refreshes last_seen. Registered devices are
    processed normally regardless of the autoconfig mode. Unknown
    devices: 404 with autoconfig disabled; with autoconfig enabled the
    heartbeat is accepted (202) and kept as a pending discovery - never
    as an inventory row."""
    result = await service.heartbeat(device_uid, payload)
    if isinstance(result, PendingHeartbeat):
        return JSONResponse(
            status_code=status.HTTP_202_ACCEPTED,
            content={
                "device_uid": result.device_uid,
                "status": "pending_registration",
                "last_seen": result.last_seen.isoformat(),
            },
        )
    device = result
    return HeartbeatResponse(
        device_uid=device.device_uid,
        status=device.status,
        device_state=device.device_state,
        current_media=device.current_media,
        payload=device.payload,
        last_seen=device.last_seen,
    )


@router.put(
    "/{device_uid}/assignment",
    response_model=AssignmentSetResult,
    summary="Assign a media to a device",
)
async def assign_media(
    device_uid: str,
    payload: AssignmentCreate,
    actor: User = Depends(require_permission("content.manage")),
    service: AssignmentService = Depends(get_assignment_service),
):
    """Set the single vigente media assignment of a device. Reassigning
    updates the existing assignment (never concurrent active ones). The
    sync state is computed against what the device currently reports:
    `synchronized` when it reports playing this exact media id,
    `pending` otherwise. The client identifies the media by its numeric
    id (`payload.current_media` in heartbeats); media names are never
    compared.

    Three different guarantees, never conflated:
    - `delivered` (this response): the `playback.command` was written to
      the device's live WebSocket without error. Strictly a send; no
      receipt or execution confirmation. The ACK watchdog closes the
      channel if this command is never answered.
    - ACK/error (server logs only): the device received and processed
      the order; never changes `sync_status`.
    - `sync_status` (GET /api/assignments): the device CONFIRMS playback
      exclusively through its heartbeat (`current_media`). If the
      device was not connected, the persisted assignment reaches it via
      `playback.sync` on its next connection.
    """
    return await service.assign(device_uid, payload.media_id)


@router.post(
    "/{device_uid}/power",
    response_model=DevicePowerResult,
    status_code=status.HTTP_200_OK,
    summary="Send a screen power command to a device",
)
async def send_power_command(
    device_uid: str,
    payload: DevicePowerAction,
    actor: User = Depends(require_permission("devices.control")),
    service: DeviceService = Depends(get_device_service),
    registry: PowerControllerRegistry = Depends(get_power_controller_registry),
):
    """Execute a power action (`on`/`off`) through the controller
    registered for the device's `type`. Native controllers (e.g. ADB for
    Android TV boxes) run server-side against the IP the device last
    reported in its heartbeat; types without a native controller fall
    back to the device's live WebSocket channel (409 while it is down).

    The response reports the attempt (`method`, `executed`, `success`,
    `detail`), never the authoritative state: the device keeps reporting
    `device_state` through its heartbeats, and that is what the UI must
    reflect."""
    device = await service.get_device(device_uid)  # 404 through the global handler

    controller = registry.for_device(device)
    if controller.requires_live_channel and not connection_manager.has(device_uid):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Device has no open WebSocket channel; power commands for this device type are delivered through it",
        )

    settings = get_settings()
    try:
        result = await asyncio.wait_for(
            controller.turn_on(device) if payload.action == "on" else controller.turn_off(device),
            timeout=settings.CAUCE_POWER_TOTAL_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=f"Power command '{payload.action}' timed out after {settings.CAUCE_POWER_TOTAL_TIMEOUT_S}s",
        ) from None

    # command_id/delivered only make sense for the WebSocket fallback.
    command_id = None
    delivered = False
    if isinstance(controller, WebSocketPowerController):
        command_id = controller.last_command_id
        delivered = result.success

    return DevicePowerResult(
        device_uid=device_uid,
        action=payload.action,
        method=result.method,
        executed=result.executed,
        success=result.success,
        detail=result.detail,
        command_id=command_id,
        delivered=delivered,
    )


@router.websocket("/{device_uid}/ws")
async def device_playback_socket(websocket: WebSocket, device_uid: str) -> None:
    """Device playback channel: WS /api/devices/{device_uid}/ws.

    Device protocol: no user credentials (same as the heartbeat; device
    authentication arrives with the security phase). Only registered
    devices are accepted. On connect the device receives `playback.sync`
    with the PERSISTED vigente assignment (or an explicit null). While
    connected it receives `playback.command` on every assignment change.
    This channel never replaces the heartbeat: it does not determine
    liveness nor reports what the device plays.

    Connection URL from the LAN: ws://<IP_SERVIDOR>:8000/api/devices/<device_uid>/ws
    """
    # Device-key check first: same shared secret as the heartbeat, sent
    # in the X-Device-Key handshake header when CAUCE_DEVICE_SECRET is
    # configured.
    if not verify_device_key(websocket.headers.get("x-device-key")):
        await websocket.close(code=WSC_POLICY_VIOLATION, reason="Invalid device key")
        return

    # Short-lived DB access: validate the device and build the initial
    # sync from PostgreSQL, then keep the socket loop database-free.
    # Any unexpected failure here (DB down, pool exhausted) must never
    # escape as a raw HTTP 500 during the handshake: it is logged and
    # surfaced as a 1011 close so the client retries with its backoff.
    try:
        async with AsyncSessionLocal() as session:
            service = DeviceService(session)
            try:
                device = await service.get_device(device_uid)
            except NotFoundError:
                await websocket.close(
                    code=WSC_POLICY_VIOLATION, reason="Device not registered"
                )
                return
            row = await service.assignments.get_with_details(device.id)
    except Exception:
        logger.exception(
            "Playback WS handshake failed for %s: database access error", device_uid
        )
        await websocket.close(code=WSC_INTERNAL_ERROR, reason="Internal server error")
        return
    sync_message = build_sync_message(device_uid, row)

    await connection_manager.connect(device_uid, websocket)
    try:
        await websocket.accept()
        await websocket.send_text(json.dumps(sync_message))
        while True:
            raw = await websocket.receive_text()
            if len(raw) > MAX_INBOUND_MESSAGE_BYTES:
                await websocket.close(
                    code=WSC_MESSAGE_TOO_LARGE, reason="Message too large"
                )
                break
            message = parse_client_message(raw)
            if message is None:
                logger.info("Ignored malformed playback message from %s", device_uid)
                continue
            # ACKs/errors only confirm receipt: they never touch
            # current_media or the sync state (heartbeats do that) and
            # are only accepted for THIS device's last command.
            if isinstance(message, (PowerAck, PowerClientError)):
                if connection_manager.matches_power_command(
                    device_uid, message.command_id
                ):
                    if message.type == "power.ack":
                        logger.info(
                            "Power ack from %s for command %d",
                            device_uid,
                            message.command_id,
                        )
                    else:
                        logger.warning(
                            "Power error from %s for command %d: [%s] %s",
                            device_uid,
                            message.command_id,
                            message.error.code,
                            message.error.message,
                        )
                else:
                    logger.warning(
                        "Ignored power %s from %s: stale/foreign command %d",
                        message.type,
                        device_uid,
                        message.command_id,
                    )
                continue
            if connection_manager.matches_last_command(
                device_uid, message.assignment_id, message.revision
            ):
                # A matching answer cancels the ACK watchdog of THIS
                # command; a stale ACK never cancels a newer pending one.
                connection_manager.note_response(
                    device_uid, message.assignment_id, message.revision
                )
                logger.info(
                    "Playback %s from %s for assignment %d rev %d",
                    message.type,
                    device_uid,
                    message.assignment_id,
                    message.revision,
                )
            else:
                logger.warning(
                    "Ignored playback %s from %s: stale/foreign assignment %d rev %d",
                    message.type,
                    device_uid,
                    message.assignment_id,
                    message.revision,
                )
    except WebSocketDisconnect:
        pass
    finally:
        connection_manager.disconnect(device_uid, websocket)
