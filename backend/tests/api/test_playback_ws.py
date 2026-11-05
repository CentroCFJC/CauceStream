"""Playback WebSocket tests.

The endpoint is exercised directly with a FakeWebSocket (the ASGI
transport used by the HTTP fixtures does not speak WebSocket), with the
endpoint's session factory swapped for one bound to the same test
database as the HTTP client.
"""

import asyncio
import json

import pytest
from starlette.websockets import WebSocketDisconnect

from app.api.routes.devices import device_playback_socket
from app.core.ws import (
    WSC_ACK_TIMEOUT,
    WSC_INTERNAL_ERROR,
    WSC_MESSAGE_TOO_LARGE,
    WSC_POLICY_VIOLATION,
    WSC_REPLACED,
    connection_manager,
)
from app.models import Media
from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)

UID = "CAUCE-001"
_DISCONNECT = object()


class FakeWebSocket:
    """Minimal starlette.WebSocket double used by the endpoint tests."""

    def __init__(self):
        self.accepted = False
        self.closed: tuple[int, str | None] | None = None
        self.sent: list[dict] = []
        self._incoming: asyncio.Queue = asyncio.Queue()

    # --- server side of the socket ---

    async def accept(self) -> None:
        self.accepted = True

    async def close(self, code: int = 1000, reason: str | None = None) -> None:
        self.closed = (code, reason)

    async def send_text(self, data: str) -> None:
        self.sent.append(json.loads(data))

    async def receive_text(self) -> str:
        item = await self._incoming.get()
        if item is _DISCONNECT:
            raise WebSocketDisconnect(1000)
        return item

    # --- test helpers ---

    def push(self, payload) -> None:
        if isinstance(payload, dict):
            payload = json.dumps(payload)
        self._incoming.put_nowait(payload)

    def client_disconnect(self) -> None:
        self._incoming.put_nowait(_DISCONNECT)

    async def wait_for(self, count: int, timeout: float = 2.0) -> list[dict]:
        async with asyncio.timeout(timeout):
            while len(self.sent) < count:
                await asyncio.sleep(0)
        return self.sent


@pytest.fixture(autouse=True)
def _clean_connections():
    connection_manager.reset()
    yield
    connection_manager.reset()


@pytest.fixture
def ws_sessionmaker(db_engine, db_session):
    """Session factory bound to the same test database the HTTP client
    uses, replacing AsyncSessionLocal inside the endpoint."""
    from sqlalchemy.ext.asyncio import async_sessionmaker

    return async_sessionmaker(db_engine, expire_on_commit=False)


async def register_device(client, token, uid=UID):
    response = await client.post(
        "/api/devices",
        json={
            "device_uid": uid,
            "name": f"Pantalla {uid}",
            "type": "screen",
            "ip_address": "10.15.1.151",
            "port": 8001,
        },
        headers=bearer(token),
    )
    assert response.status_code == 201, response.text


async def create_media(db_session, name="Loop sala") -> int:
    media = Media(name=name, media_type="url", external_url="https://example.com/x")
    db_session.add(media)
    await db_session.commit()
    return media.id


async def open_socket(monkeypatch, ws_sessionmaker, uid=UID):
    monkeypatch.setattr(
        "app.api.routes.devices.AsyncSessionLocal", ws_sessionmaker
    )
    ws = FakeWebSocket()
    task = asyncio.create_task(device_playback_socket(ws, uid))
    return ws, task


async def close_socket(ws, task):
    ws.client_disconnect()
    async with asyncio.timeout(2):
        await task


# --- Connection lifecycle ---


async def test_registered_device_receives_initial_sync(client, admin, monkeypatch, ws_sessionmaker):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    messages = await ws.wait_for(1)

    assert ws.accepted
    assert ws.closed is None
    assert connection_manager.has(UID)
    sync = messages[0]
    assert sync["type"] == "playback.sync"
    assert sync["protocol"] == 1
    assert sync["device_uid"] == UID
    assert sync["assignment"] is None  # explicit no-assignment state
    assert sync["sent_at"]

    await close_socket(ws, task)
    assert not connection_manager.has(UID)


async def test_unknown_uid_rejected(client, admin, monkeypatch, ws_sessionmaker):
    ws, task = await open_socket(monkeypatch, ws_sessionmaker, uid="CAUCE-GHOST")
    await task

    assert not ws.accepted
    assert ws.closed == (WSC_POLICY_VIOLATION, "Device not registered")
    assert not connection_manager.has("CAUCE-GHOST")


async def test_database_failure_during_handshake_closes_with_internal_error(
    monkeypatch,
):
    """A transient DB failure must never escape as a raw HTTP 500 in
    the handshake: it is logged and the socket is closed with 1011
    (the client retries with its backoff)."""
    class FailingSessionFactory:
        def __call__(self):
            raise RuntimeError("database unavailable")

    monkeypatch.setattr(
        "app.api.routes.devices.AsyncSessionLocal", FailingSessionFactory()
    )
    ws = FakeWebSocket()
    await device_playback_socket(ws, UID)

    assert not ws.accepted
    assert ws.closed == (WSC_INTERNAL_ERROR, "Internal server error")
    assert not connection_manager.has(UID)


async def test_duplicate_connection_is_replaced(
    client, admin, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    ws1, task1 = await open_socket(monkeypatch, ws_sessionmaker)
    await ws1.wait_for(1)
    ws2, task2 = await open_socket(monkeypatch, ws_sessionmaker)
    await ws2.wait_for(1)

    # The newest connection wins; the old one is explicitly closed.
    assert ws1.closed == (WSC_REPLACED, "Replaced by a newer connection")
    assert connection_manager.has(UID)
    assert connection_manager._connections[UID] is ws2

    await close_socket(ws2, task2)
    ws1.client_disconnect()
    await task1
    assert not connection_manager.has(UID)


# --- Initial state and reconnection ---


async def test_sync_contains_persisted_assignment(
    client, admin, db_session, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    # Assigned while the device was DISCONNECTED: it must be delivered
    # on reconnect (built from PostgreSQL, not from memory).
    response = await client.put(
        f"/api/devices/{UID}/assignment",
        json={"media_id": media_id},
        headers=bearer(token),
    )
    assert response.status_code == 200
    assert response.json()["revision"] == 1

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    messages = await ws.wait_for(1)
    assignment = messages[0]["assignment"]
    assert assignment["assignment_id"] == response.json()["id"]
    assert assignment["media_id"] == media_id
    assert assignment["revision"] == 1
    assert assignment["sync_status"] == "pending"
    assert assignment["media"]["name"] == "Loop sala"
    assert assignment["media"]["media_type"] == "url"
    assert assignment["media"]["external_url"] == "https://example.com/x"
    # No invented URLs for url media: the file endpoint is not offered.
    assert assignment["media"]["file_url"] is None

    await close_socket(ws, task)


async def test_file_media_sync_uses_existing_download_endpoint(
    client, admin, db_session, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media = Media(name="portada.png", media_type="image", mime_type="image/png",
                  file_size=10, storage_key="images/x.png")
    db_session.add(media)
    await db_session.commit()

    response = await client.put(
        f"/api/devices/{UID}/assignment",
        json={"media_id": media.id},
        headers=bearer(token),
    )
    assert response.status_code == 200

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    messages = await ws.wait_for(1)
    payload_media = messages[0]["assignment"]["media"]
    assert payload_media["file_url"] == f"/api/media/{media.id}/file"
    assert payload_media["external_url"] is None

    await close_socket(ws, task)


# --- Live commands ---


async def test_command_sent_while_connected_and_newest_wins(
    client, admin, db_session, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    first = await create_media(db_session, name="Primero")
    second = await create_media(db_session, name="Segundo")

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)  # initial sync

    async def assign(media_id):
        response = await client.put(
            f"/api/devices/{UID}/assignment",
            json={"media_id": media_id},
            headers=bearer(token),
        )
        assert response.status_code == 200

    # Two rapid changes: the newest command must be the last delivered
    # state; an older order can never overwrite the latest one.
    await assign(first)
    await assign(second)

    messages = await ws.wait_for(3)
    assert [m["type"] for m in messages] == [
        "playback.sync",
        "playback.command",
        "playback.command",
    ]
    assert messages[1]["assignment"]["revision"] == 1
    assert messages[1]["assignment"]["media_id"] == first
    assert messages[2]["assignment"]["revision"] == 2  # monotonic
    assert messages[2]["assignment"]["media_id"] == second
    last = connection_manager._last_command[UID]
    assert last["assignment"]["revision"] == 2

    await close_socket(ws, task)


# --- Inbound messages ---


async def test_ack_and_error_validated_against_last_command(
    client, admin, db_session, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    response = await client.put(
        f"/api/devices/{UID}/assignment",
        json={"media_id": media_id},
        headers=bearer(token),
    )
    await ws.wait_for(2)
    assignment_id = response.json()["id"]

    # Valid ACK: accepted (logged), no state change, connection alive.
    ws.push({"type": "playback.ack", "assignment_id": assignment_id, "revision": 1})
    # Processing error: accepted (logged), connection alive.
    ws.push({
        "type": "playback.error",
        "assignment_id": assignment_id,
        "revision": 1,
        "error": {"code": "download_failed", "message": "403 al descargar"},
    })
    # Stale/foreign confirmation: ignored, connection stays alive.
    ws.push({"type": "playback.ack", "assignment_id": 9999, "revision": 42})
    # Garbage: ignored.
    ws.push("not-json")
    await asyncio.sleep(0.05)
    assert ws.closed is None
    assert connection_manager.has(UID)

    # The ACK never marked the assignment as played: still pending
    # (only a heartbeat with current_media changes that).
    listing = await client.get("/api/assignments", headers=bearer(token))
    assert listing.json()[0]["sync_status"] == "pending"

    # Oversized message: closed with 1009 and cleaned up.
    ws.push("x" * (8 * 1024 + 1))
    await asyncio.sleep(0.05)
    assert ws.closed == (WSC_MESSAGE_TOO_LARGE, "Message too large")
    await task
    assert not connection_manager.has(UID)


async def test_send_failure_is_isolated(client, admin, monkeypatch, ws_sessionmaker):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    class BrokenSocket(FakeWebSocket):
        async def send_text(self, data: str) -> None:
            raise RuntimeError("peer vanished")

    broken = BrokenSocket()
    replaced = await connection_manager.connect(UID, broken)
    assert replaced  # supersedes the healthy one

    # A failing send must not raise into the caller (the HTTP request).
    delivered = await connection_manager.send_command(
        UID, {"type": "playback.command", "assignment": {"revision": 1}}
    )
    assert delivered is False
    assert not connection_manager.has(UID)  # broken connection cleaned up

    ws.client_disconnect()
    await task


# --- ws_connected exposure (device inventory) ---


async def test_detail_reports_live_ws_state(
    client, admin, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    detail = await client.get(f"/api/devices/{UID}", headers=bearer(token))
    assert detail.status_code == 200
    assert detail.json()["ws_connected"] is False

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    detail = await client.get(f"/api/devices/{UID}", headers=bearer(token))
    assert detail.json()["ws_connected"] is True

    await close_socket(ws, task)
    detail = await client.get(f"/api/devices/{UID}", headers=bearer(token))
    assert detail.json()["ws_connected"] is False


async def test_list_reports_live_ws_state_per_device(
    client, admin, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token, uid=UID)
    await register_device(client, token, uid="CAUCE-002")

    ws, task = await open_socket(monkeypatch, ws_sessionmaker, uid=UID)
    await ws.wait_for(1)

    listing = await client.get("/api/devices", headers=bearer(token))
    assert listing.status_code == 200
    by_uid = {d["device_uid"]: d["ws_connected"] for d in listing.json()}
    assert by_uid[UID] is True
    assert by_uid["CAUCE-002"] is False

    await close_socket(ws, task)


# --- ACK watchdog (dead channel detection) ---

# Tests patch the deadline down to keep the suite fast; production runs
# with ws.ACK_TIMEOUT_SECONDS (10 s).
WATCHDOG_TEST_TIMEOUT = 0.05


@pytest.fixture
def fast_watchdog(monkeypatch):
    monkeypatch.setattr("app.core.ws.ACK_TIMEOUT_SECONDS", WATCHDOG_TEST_TIMEOUT)


async def assign_media(client, token, media_id, uid=UID):
    response = await client.put(
        f"/api/devices/{uid}/assignment",
        json={"media_id": media_id},
        headers=bearer(token),
    )
    assert response.status_code == 200, response.text
    return response.json()


async def test_dead_channel_closed_on_ack_timeout(
    client, admin, db_session, monkeypatch, ws_sessionmaker, fast_watchdog
):
    """A delivered command that is never answered closes the channel:
    ws_connected stops reporting a half-open socket as alive."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    result = await assign_media(client, token, media_id)
    assert result["delivered"] is True
    await ws.wait_for(2)  # sync + command

    # No ACK ever arrives: the deadline closes the dead channel.
    await asyncio.sleep(WATCHDOG_TEST_TIMEOUT * 4)
    assert ws.closed == (WSC_ACK_TIMEOUT, "Playback ACK timeout")
    assert not connection_manager.has(UID)

    # The live inventory (what the admin UI polls) reflects it.
    listing = await client.get("/api/devices", headers=bearer(token))
    assert listing.json()[0]["ws_connected"] is False

    ws.client_disconnect()
    await task


async def test_matching_ack_cancels_watchdog(
    client, admin, db_session, monkeypatch, ws_sessionmaker, fast_watchdog
):
    """An ACK for the exact pending command cancels the deadline: a
    healthy channel is never closed."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    result = await assign_media(client, token, media_id)
    await ws.wait_for(2)
    ws.push(
        {
            "type": "playback.ack",
            "assignment_id": result["id"],
            "revision": result["revision"],
        }
    )
    await asyncio.sleep(WATCHDOG_TEST_TIMEOUT * 4)

    assert ws.closed is None
    assert connection_manager.has(UID)

    await close_socket(ws, task)


async def test_stale_ack_does_not_cancel_newer_watchdog(
    client, admin, db_session, monkeypatch, ws_sessionmaker, fast_watchdog
):
    """An ACK for an OLDER command must not cancel the watchdog of a
    newer delivery: correlation is (assignment_id, revision), not uid."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    first = await create_media(db_session, name="Primero")
    second = await create_media(db_session, name="Segundo")

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    old = await assign_media(client, token, first)
    new = await assign_media(client, token, second)
    await ws.wait_for(3)  # sync + command + command

    # Stale ACK for revision 1 while revision 2 is the pending one.
    ws.push(
        {
            "type": "playback.ack",
            "assignment_id": old["id"],
            "revision": old["revision"],
        }
    )
    await asyncio.sleep(WATCHDOG_TEST_TIMEOUT * 4)

    assert ws.closed == (WSC_ACK_TIMEOUT, "Playback ACK timeout")
    assert not connection_manager.has(UID)

    ws.client_disconnect()
    await task


async def test_reconnect_with_pending_watchdog_keeps_new_socket(
    client, admin, db_session, monkeypatch, ws_sessionmaker, fast_watchdog
):
    """A fresh connection replaces the pending watchdog (its sync
    supersedes the old command): the deadline never closes the NEW
    socket."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    dead, dead_task = await open_socket(monkeypatch, ws_sessionmaker)
    await dead.wait_for(1)
    await assign_media(client, token, media_id)
    await dead.wait_for(2)  # delivered to the (soon dead) socket

    fresh, fresh_task = await open_socket(monkeypatch, ws_sessionmaker)
    await fresh.wait_for(1)  # replacement + fresh playback.sync
    assert dead.closed == (WSC_REPLACED, "Replaced by a newer connection")

    await asyncio.sleep(WATCHDOG_TEST_TIMEOUT * 4)
    assert fresh.closed is None
    assert connection_manager.has(UID)

    # The new channel still receives commands normally.
    result = await assign_media(client, token, media_id)
    assert result["delivered"] is True
    await fresh.wait_for(2)

    dead.client_disconnect()
    await dead_task
    await close_socket(fresh, fresh_task)


async def test_assignment_without_channel_reports_delivered_false(
    client, admin, db_session
):
    """`delivered` is strictly the write to a live socket: with no
    channel the assignment persists and reports False."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    result = await assign_media(client, token, media_id)

    assert result["delivered"] is False
    # The assignment is persisted: the device will get it through
    # playback.sync on its next connection (test_sync_contains_persisted_
    # assignment covers that delivery).
    listing = await client.get("/api/assignments", headers=bearer(token))
    assert listing.json()[0]["media_id"] == media_id
    assert listing.json()[0]["sync_status"] == "pending"


async def test_late_ack_after_timeout_is_isolated(
    client, admin, db_session, monkeypatch, ws_sessionmaker, fast_watchdog
):
    """An ACK arriving after the deadline (channel already closed by the
    watchdog) is processed without breaking anything."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)
    result = await assign_media(client, token, media_id)
    await ws.wait_for(2)

    await asyncio.sleep(WATCHDOG_TEST_TIMEOUT * 4)
    assert ws.closed == (WSC_ACK_TIMEOUT, "Playback ACK timeout")

    # Late answer: validated, no pending watchdog, no crash.
    ws.push(
        {
            "type": "playback.ack",
            "assignment_id": result["id"],
            "revision": result["revision"],
        }
    )
    await asyncio.sleep(0.05)
    assert ws.closed == (WSC_ACK_TIMEOUT, "Playback ACK timeout")

    ws.client_disconnect()
    await task


# --- Power commands (screen standby) ---


async def power(client, token, action, uid=UID):
    return await client.post(
        f"/api/devices/{uid}/power",
        json={"action": action},
        headers=bearer(token),
    )


async def test_power_command_delivered_while_connected(
    client, admin, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)  # initial playback sync

    response = await power(client, token, "off")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["device_uid"] == UID
    assert body["action"] == "off"
    assert body["method"] == "websocket"  # type "screen" -> fallback WS
    assert body["delivered"] is True
    assert body["success"] is True
    assert body["executed"] is True
    assert body["command_id"] == 1

    messages = await ws.wait_for(2)
    command = messages[-1]
    assert command["type"] == "power.command"
    assert command["protocol"] == 1
    assert command["device_uid"] == UID
    assert command["command_id"] == 1
    assert command["action"] == "off"
    assert command["sent_at"]

    # The second command gets the next monotonic id of this device.
    response = await power(client, token, "on")
    assert response.json()["command_id"] == 2
    messages = await ws.wait_for(3)
    assert messages[-1]["action"] == "on"
    assert messages[-1]["command_id"] == 2

    await close_socket(ws, task)


async def test_power_command_requires_live_channel_or_known_device(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    # Unknown device: 404 (never a phantom command id).
    unknown = await power(client, token, "off", uid="CAUCE-GHOST")
    assert unknown.status_code == 404

    # Registered but not connected: 409, nothing sent or remembered.
    no_channel = await power(client, token, "off")
    assert no_channel.status_code == 409
    assert no_channel.json()["detail"]

    # After connecting, the sequence still starts at 1: no id was
    # allocated while the channel was down.
    assert connection_manager.next_power_command_id(UID) == 1


async def test_power_command_requires_control_permission(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    assert (await power(client, mediator_token, "off")).status_code == 403
    assert (await power(client, mediator_token, "on")).status_code == 403


async def test_power_ack_and_error_validated_against_last_command(
    client, admin, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    response = await power(client, token, "off")
    command_id = response.json()["command_id"]
    await ws.wait_for(2)

    # Valid ACK: accepted (logged), connection alive, no state change.
    ws.push({"type": "power.ack", "command_id": command_id})
    # Execution error: accepted (logged), connection alive.
    ws.push(
        {
            "type": "power.error",
            "command_id": command_id,
            "error": {"code": "standby_denied", "message": "permission missing"},
        }
    )
    # Stale/foreign confirmation: ignored, connection alive.
    ws.push({"type": "power.ack", "command_id": 9999})
    # Malformed (invalid command id): ignored, connection alive.
    ws.push({"type": "power.ack", "command_id": 0})
    ws.push("not-json")
    await asyncio.sleep(0.05)

    assert ws.closed is None
    assert connection_manager.has(UID)

    # ACKs never changed the device state: nothing but heartbeats do.
    detail = await client.get(f"/api/devices/{UID}", headers=bearer(token))
    assert detail.json()["device_state"] is None

    await close_socket(ws, task)


async def test_power_command_send_failure_is_isolated(
    client, admin, monkeypatch, ws_sessionmaker
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    ws, task = await open_socket(monkeypatch, ws_sessionmaker)
    await ws.wait_for(1)

    class BrokenSocket(FakeWebSocket):
        async def send_text(self, data: str) -> None:
            if json.loads(data).get("type") == "power.command":
                raise RuntimeError("peer vanished")
            await super().send_text(data)

    broken = BrokenSocket()
    await connection_manager.connect(UID, broken)

    # A failing send must not raise into the caller (the HTTP request).
    command_id = connection_manager.next_power_command_id(UID)
    delivered = await connection_manager.send_power_command(
        UID,
        {
            "type": "power.command",
            "command_id": command_id,
            "action": "off",
            "protocol": 1,
            "device_uid": UID,
        },
    )
    assert delivered is False
    assert not connection_manager.has(UID)  # broken connection cleaned up

    ws.client_disconnect()
    await task
