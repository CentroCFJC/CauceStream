"""Device management business logic: registration, heartbeats, events,
the server-side online/offline determination and autoconfig discovery."""

from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.exceptions import ConflictError, NotFoundError
from app.models import Device, DeviceEvent, PendingDevice
from app.models.device_event import (
    EVENT_DEVICE_REGISTERED,
    EVENT_DEVICE_STATE_CHANGED,
    EVENT_IP_CHANGED,
    EVENT_MAC_CHANGED,
    EVENT_MEDIA_CHANGED,
    EVENT_NAME_CHANGED,
    EVENT_PORT_CHANGED,
    EVENT_STATUS_CHANGED,
    EVENT_TYPE_CHANGED,
)
from app.repositories import AssignmentRepository, AutoconfigRepository, DeviceRepository
from app.schemas.device import DeviceRegister, DeviceUpdate, HeartbeatPayload
from app.services.assignment_service import compute_sync_status
from app.utils.time import utc_now


def normalize_reported_media(value: int | str | None) -> str:
    """Normalize the media id reported in a heartbeat.

    The only valid identifier is a Media.id (integer >= 1, possibly
    sent as a digit string). Anything else - absent, null, a
    non-identifying string, the retired `current_application` app name -
    is NOT a media and becomes "unknown". Nothing is ever inferred.
    """
    if value is None:
        return "unknown"
    try:
        media_id = int(value)
    except (TypeError, ValueError):
        return "unknown"
    return str(media_id) if media_id >= 1 else "unknown"


@dataclass(frozen=True)
class PendingHeartbeat:
    """Heartbeat accepted from an unregistered device while autoconfig is
    enabled: stored as pending discovery data, not as an inventory row."""

    device_uid: str
    last_seen: datetime


class DeviceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.devices = DeviceRepository(session)
        self.autoconfig = AutoconfigRepository(session)
        self.assignments = AssignmentRepository(session)

    # --- Registration ---

    async def register(self, payload: DeviceRegister) -> Device:
        """Register a device. It starts offline: only a valid heartbeat
        marks it online."""
        if await self.devices.get_by_uid(payload.device_uid) is not None:
            raise ConflictError(f"Device {payload.device_uid} is already registered")

        device = Device(
            device_uid=payload.device_uid,
            name=payload.name,
            type=payload.type,
            ip_address=str(payload.ip_address) if payload.ip_address else None,
            mac_address=payload.mac_address,
            port=payload.port,
            status="offline",
            device_state=None,
            current_media=None,
            last_seen=None,
        )
        try:
            await self.devices.add(device)
            await self._add_event(device.id, EVENT_DEVICE_REGISTERED, None, None)
            # Registering a discovered device removes it from the pending
            # autoconfig list; registered devices never show as pending.
            await self.autoconfig.delete_pending(payload.device_uid)
            await self.session.commit()
        except IntegrityError as exc:
            await self.session.rollback()
            raise ConflictError(
                f"Device {payload.device_uid} is already registered"
            ) from exc
        return await self._require_device(payload.device_uid)

    # --- Queries ---

    async def list_devices(self) -> list[Device]:
        return await self.devices.list_all()

    async def get_device(self, device_uid: str) -> Device:
        return await self._require_device(device_uid)

    async def update(self, device_uid: str, payload: DeviceUpdate) -> Device:
        """Partial update of registration data (name/type/IP/MAC).

        `type` matters beyond labeling: it selects the server-side power
        controller for the device (app/power/). The row is locked so
        concurrent updates serialize; only real changes are evented.
        """
        device = await self.devices.get_by_uid(device_uid, for_update=True)
        if device is None:
            raise NotFoundError(f"Device {device_uid} not found")

        data = payload.model_dump(exclude_unset=True)
        changes: list[tuple[str, str | None, str | None]] = []

        new_name = data.get("name")
        if new_name is not None and device.name != new_name:
            changes.append((EVENT_NAME_CHANGED, device.name, new_name))
            device.name = new_name

        new_type = data.get("type")
        if new_type is not None and device.type != new_type:
            changes.append((EVENT_TYPE_CHANGED, device.type, new_type))
            device.type = new_type

        if "ip_address" in data:
            new_ip = str(data["ip_address"]) if data["ip_address"] else None
            if device.ip_address != new_ip:
                changes.append((EVENT_IP_CHANGED, device.ip_address, new_ip))
                device.ip_address = new_ip

        new_mac = data.get("mac_address")
        if new_mac is not None and device.mac_address != new_mac:
            changes.append((EVENT_MAC_CHANGED, device.mac_address, new_mac))
            device.mac_address = new_mac

        for event_type, previous, new in changes:
            await self._add_event(device.id, event_type, previous, new)
        await self.session.commit()
        # Re-fetch after commit: attributes are expired and lazy IO is not
        # allowed when the response is serialized.
        return await self._require_device(device_uid)

    async def delete_device(self, device_uid: str) -> Device:
        """Delete a registered device together with its change history
        (cascade). Pending autoconfig discoveries are separate data and
        are not affected."""
        device = await self._require_device(device_uid)
        await self.devices.delete(device)
        await self.session.commit()
        return device

    async def list_events(self, device_uid: str) -> list[DeviceEvent]:
        device = await self._require_device(device_uid)
        return await self.devices.list_events(device.id)

    # --- Heartbeat ---

    async def heartbeat(
        self, device_uid: str, payload: HeartbeatPayload
    ) -> Device | PendingHeartbeat:
        """Process one heartbeat: refresh state and record only changes.

        The row is locked (FOR UPDATE) so concurrent heartbeats of the same
        device are serialized and cannot emit duplicated change events.

        Device-specific attributes live in `payload.payload`: they are
        merged per key into the stored JSON, so an omitted or empty payload
        leaves the previous values untouched (absence never means
        false/zero/null) and an equivalent payload produces no write.
        Payload changes are not evented: metrics like battery level change
        on every heartbeat and would flood the history.
        """
        device = await self.devices.get_by_uid(device_uid, for_update=True)
        if device is None:
            # Devices are never auto-created from heartbeats. With
            # autoconfig disabled the heartbeat is simply rejected; with
            # autoconfig enabled the unknown device is kept as pending
            # discovery data for the administrator to register.
            if not await self.autoconfig.is_enabled():
                raise NotFoundError(f"Device {device_uid} not found")

            reported_payload = payload.payload.model_dump(exclude_none=True)
            pending = await self.autoconfig.upsert_pending(
                device_uid=device_uid,
                ip_address=str(payload.ip_address),
                device_state=payload.device_state,
                payload=reported_payload or None,
                last_seen=utc_now(),
            )
            await self.session.commit()
            return PendingHeartbeat(
                device_uid=pending.device_uid, last_seen=pending.last_seen
            )

        new_ip = str(payload.ip_address)
        changes: list[tuple[str, str | None, str | None]] = []

        # A valid heartbeat proves connectivity: the server decides status.
        if device.status != "online":
            changes.append((EVENT_STATUS_CHANGED, device.status, "online"))
            device.status = "online"

        if device.ip_address != new_ip:
            changes.append((EVENT_IP_CHANGED, device.ip_address, new_ip))
            device.ip_address = new_ip

        # The MAC is a general field like the IP: only a reported MAC
        # updates it; absence keeps the previous value (needed for
        # server-side Wake-on-LAN power-on).
        if payload.mac_address is not None and device.mac_address != payload.mac_address:
            changes.append((EVENT_MAC_CHANGED, device.mac_address, payload.mac_address))
            device.mac_address = payload.mac_address

        # The port is a device-specific attribute: only a reported port
        # updates the inventory column; absence keeps the previous value.
        reported_port = payload.payload.port
        if reported_port is not None and device.port != reported_port:
            changes.append((
                EVENT_PORT_CHANGED,
                str(device.port) if device.port is not None else None,
                str(reported_port),
            ))
            device.port = reported_port

        if device.device_state != payload.device_state:
            changes.append((
                EVENT_DEVICE_STATE_CHANGED,
                device.device_state,
                payload.device_state,
            ))
            device.device_state = payload.device_state

        # The current media is a device-specific attribute (like the
        # port): the Media.id reported in `payload.current_media`.
        # Absent/null/non-identifying values become "unknown" (the
        # reported media is explicitly re-established on every
        # heartbeat; absence is NOT "keep the previous one" here). The
        # retired `current_application`, if a legacy client still sends
        # it, is never interpreted as media.
        reported_media = normalize_reported_media(payload.payload.current_media)
        if device.current_media != reported_media:
            changes.append((
                EVENT_MEDIA_CHANGED,
                device.current_media,
                reported_media,
            ))
            device.current_media = reported_media

        # Sync state of the vigente assignment (if any) is recomputed
        # inside the same transaction as the current_media update.
        assignment = await self.assignments.get_by_device_id(device.id)
        if assignment is not None:
            sync_status = compute_sync_status(reported_media, assignment.media_id)
            if assignment.sync_status != sync_status:
                assignment.sync_status = sync_status

        # Merge reported device-specific attributes into the stored
        # payload. `current_media` is excluded: it lives in its own
        # column and the payload JSON stays for device metrics.
        reported = payload.payload.model_dump(
            exclude_none=True, exclude={"current_media"}
        )
        stored = device.payload or {}
        merged = {**stored, **reported}
        if merged != stored:
            device.payload = merged

        # Always refresh last_seen, even when nothing else changed.
        device.last_seen = utc_now()

        for event_type, previous, new in changes:
            await self._add_event(device.id, event_type, previous, new)
        await self.session.commit()
        return await self.devices.get_by_uid(device_uid)

    # --- Offline sweep (server-side connectivity determination) ---

    async def mark_stale_devices_offline(self) -> int:
        """Mark devices whose last heartbeat is older than the allowed
        interval as offline, recording one status_changed event each.
        Repeated sweeps without recovery emit no new events."""
        cutoff = utc_now() - timedelta(
            seconds=get_settings().DEVICE_OFFLINE_AFTER_SECONDS
        )
        stale = await self.devices.stale_online_devices(cutoff)
        for device in stale:
            device.status = "offline"
            await self._add_event(device.id, EVENT_STATUS_CHANGED, "online", "offline")
        if stale:
            await self.session.commit()
        return len(stale)

    # --- Autoconfig discovery ---

    async def set_autoconfig_enabled(self, enabled: bool) -> bool:
        """Toggle the autoconfig discovery mode (DB-backed, shared by all
        workers). Disabling also clears the pending list: stale discovery
        data must never be reused while the mode is off. Registered devices
        are never touched."""
        await self.autoconfig.set_enabled(enabled)
        if not enabled:
            await self.autoconfig.delete_all()
        await self.session.commit()
        return enabled

    async def list_pending_devices(self) -> list[PendingDevice]:
        """Unknown devices with a heartbeat inside the TTL window.

        Lazy maintenance: expired rows and rows that became registered
        are removed before listing, so absence of heartbeats alone
        determines the expiry of a discovery."""
        cutoff = utc_now() - timedelta(
            seconds=get_settings().AUTOCONFIG_PENDING_TTL_SECONDS
        )
        changed = await self.autoconfig.delete_expired(cutoff)
        changed += await self.autoconfig.delete_registered()
        if changed:
            await self.session.commit()
        return await self.autoconfig.list_fresh(cutoff)

    async def purge_stale_pending(self) -> int:
        """Sweep-side cleanup of pending discoveries (expired/registered)."""
        cutoff = utc_now() - timedelta(
            seconds=get_settings().AUTOCONFIG_PENDING_TTL_SECONDS
        )
        changed = await self.autoconfig.delete_expired(cutoff)
        changed += await self.autoconfig.delete_registered()
        if changed:
            await self.session.commit()
        return changed

    async def reset_autoconfig(self) -> None:
        """Startup reset: the mode is always off after a backend restart,
        never accidentally left enabled."""
        await self.autoconfig.set_enabled(False)
        await self.autoconfig.delete_all()
        await self.session.commit()

    # --- Internals ---

    async def _require_device(self, device_uid: str) -> Device:
        device = await self.devices.get_by_uid(device_uid)
        if device is None:
            raise NotFoundError(f"Device {device_uid} not found")
        return device

    async def _add_event(
        self, device_id: int, event_type: str, previous: str | None, new: str | None
    ) -> None:
        self.session.add(
            DeviceEvent(
                device_id=device_id,
                event_type=event_type,
                previous_value=previous,
                new_value=new,
            )
        )
        await self.session.flush()
