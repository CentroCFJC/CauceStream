"""Shared device-key authentication tests (X-Device-Key / CAUCE_DEVICE_SECRET).

The secret is toggled per test by mutating the cached settings instance,
so the rest of the suite keeps running in transition mode (no secret
configured), exactly like a server before rollout.
"""

import asyncio
import json

import pytest
from starlette.websockets import WebSocketDisconnect

from app.api.routes.devices import device_playback_socket
from app.core.config import get_settings
from app.core.ws import WSC_POLICY_VIOLATION, connection_manager
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
SECRET = "test-device-secret"
_DISCONNECT = object()


class FakeWebSocket:
    def __init__(self, headers: dict | None = None):
        self.headers = {k.lower(): v for k, v in (headers or {}).items()}
        self.accepted = False
        self.closed: tuple[int, str | None] | None = None
        self.sent: list[dict] = []
        self._queue: asyncio.Queue = asyncio.Queue()

    async def accept(self) -> None:
        self.accepted = True

    async def close(self, code: int = 1000, reason: str | None = None) -> None:
        self.closed = (code, reason)

    async def send_text(self, data: str) -> None:
        self.sent.append(json.loads(data))

    async def receive_text(self) -> str:
        item = await self._queue.get()
        if item is _DISCONNECT:
            raise WebSocketDisconnect(1000)
        return item

    def client_disconnect(self) -> None:
        self._queue.put_nowait(_DISCONNECT)


@pytest.fixture(autouse=True)
def _clean_connections():
    connection_manager.reset()
    yield
    connection_manager.reset()


@pytest.fixture
def device_secret(monkeypatch):
    """Enable the shared secret for one test."""
    monkeypatch.setattr(get_settings(), "CAUCE_DEVICE_SECRET", SECRET, raising=False)
    yield SECRET
    # monkeypatch restores the original value automatically.


@pytest.fixture
def no_secret(monkeypatch):
    monkeypatch.setattr(get_settings(), "CAUCE_DEVICE_SECRET", "", raising=False)
    yield


async def register_device(client, token, uid=UID):
    response = await client.post(
        "/api/devices",
        json={
            "device_uid": uid,
            "name": "Pantalla",
            "type": "screen",
            "ip_address": "10.15.1.151",
            "port": 8001,
        },
        headers=bearer(token),
    )
    assert response.status_code == 201, response.text


async def heartbeat(client, key: str | None = None):
    headers = {"X-Device-Key": key} if key is not None else {}
    return await client.post(
        f"/api/devices/{UID}/heartbeat",
        json={"ip_address": "10.15.1.151", "device_state": "active"},
        headers=headers,
    )


# --- Heartbeat ---


async def test_heartbeat_rejected_without_key_when_secret_set(
    client, admin, device_secret
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    missing = await heartbeat(client)
    assert missing.status_code == 401
    assert missing.json()["code"] == "device_key_invalid"

    wrong = await heartbeat(client, key="wrong-secret")
    assert wrong.status_code == 401

    ok = await heartbeat(client, key=SECRET)
    assert ok.status_code == 200
    assert ok.json()["status"] == "online"


async def test_heartbeat_open_without_secret_configured(client, admin, no_secret):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await heartbeat(client)  # transition mode: no key needed
    assert response.status_code == 200


# --- WebSocket ---


async def test_ws_rejected_without_key_when_secret_set(
    client, admin, db_engine, db_session, device_secret, monkeypatch
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    from sqlalchemy.ext.asyncio import async_sessionmaker

    maker = async_sessionmaker(db_engine, expire_on_commit=False)
    monkeypatch.setattr("app.api.routes.devices.AsyncSessionLocal", maker)

    no_key = FakeWebSocket()
    await device_playback_socket(no_key, UID)
    assert no_key.closed == (WSC_POLICY_VIOLATION, "Invalid device key")
    assert not connection_manager.has(UID)

    wrong_key = FakeWebSocket(headers={"X-Device-Key": "nope"})
    await device_playback_socket(wrong_key, UID)
    assert wrong_key.closed == (WSC_POLICY_VIOLATION, "Invalid device key")

    good_key = FakeWebSocket(headers={"X-Device-Key": SECRET})
    task = asyncio.create_task(device_playback_socket(good_key, UID))
    async with asyncio.timeout(2):
        while not good_key.sent:
            await asyncio.sleep(0)
    assert good_key.accepted
    assert good_key.sent[0]["type"] == "playback.sync"
    assert connection_manager.has(UID)

    good_key.client_disconnect()
    await task


# --- Media file download (dual auth) ---


async def create_file_media(db_session) -> int:
    """Library record plus its physical file (the download streams it)."""
    from pathlib import Path

    from tests.conftest import MEDIA_TEST_DIR

    record = Media(
        name="portada.png",
        media_type="image",
        mime_type="image/png",
        file_size=9,
        storage_key="images/x.png",
    )
    db_session.add(record)
    await db_session.commit()

    path = Path(MEDIA_TEST_DIR) / "images" / "x.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"png-data")
    return record.id


async def test_file_download_with_device_key(client, admin, db_session, device_secret):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    media_id = await create_file_media(db_session)

    response = await client.get(f"/api/media/{media_id}/file")
    assert response.status_code == 401  # neither user token nor device key

    # The shared device key is enough: no user involved.
    response = await client.get(
        f"/api/media/{media_id}/file", headers={"X-Device-Key": SECRET}
    )
    assert response.status_code == 200

    # A user with content.view still works with its own token.
    response = await client.get(
        f"/api/media/{media_id}/file", headers=bearer(token)
    )
    assert response.status_code == 200

    # A wrong device key is rejected even with no token.
    response = await client.get(
        f"/api/media/{media_id}/file", headers={"X-Device-Key": "wrong"}
    )
    assert response.status_code == 401


async def test_file_download_mediator_without_key_rejected(
    client, admin, mediator, db_session, device_secret
):
    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    media_id = await create_file_media(db_session)

    # content.view via user token is fine...
    response = await client.get(
        f"/api/media/{media_id}/file", headers=bearer(mediator_token)
    )
    assert response.status_code == 200
    # ...but a device key does not substitute a user token for other
    # admin endpoints: listing stays permission-based.
    response = await client.get("/api/media", headers={"X-Device-Key": SECRET})
    assert response.status_code == 401


async def test_admin_endpoints_do_not_accept_device_key(
    client, admin, device_secret
):
    # The device key is for the device protocol only: admin operations
    # keep requiring a user token.
    response = await client.post(
        "/api/devices",
        json={
            "device_uid": "CAUCE-X",
            "name": "X",
            "type": "screen",
        },
        headers={"X-Device-Key": SECRET},
    )
    assert response.status_code == 401
