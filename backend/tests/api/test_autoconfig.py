"""Autoconfig discovery tests: mode toggle, pending devices, expiry and
integration with the existing heartbeat/register flows."""

from datetime import timedelta

from sqlalchemy import select

from app.models import Device, PendingDevice
from app.utils.time import utc_now
from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)

UNKNOWN_UID = "tablet-ar-01"
HB_UNKNOWN = {
    "ip_address": "10.15.1.164",
    "device_state": "active",
    "payload": {"battery_level": 64},
}


async def enable_autoconfig(client, token, enabled=True):
    response = await client.post(
        "/api/devices/autoconfig",
        json={"enabled": enabled},
        headers=bearer(token),
    )
    assert response.status_code == 200, response.text
    return response.json()


async def pending_list(client, token):
    response = await client.get(
        "/api/devices/autoconfig/pending", headers=bearer(token)
    )
    assert response.status_code == 200, response.text
    return response.json()


async def register_device(client, token, uid=UNKNOWN_UID, ip="10.15.1.164"):
    response = await client.post(
        "/api/devices",
        json={
            "device_uid": uid,
            "name": f"Dispositivo {uid}",
            "type": "tablet",
            "ip_address": ip,
        },
        headers=bearer(token),
    )
    assert response.status_code == 201, response.text
    return response.json()


async def heartbeat_unknown(client, uid=UNKNOWN_UID, **overrides):
    payload = {**HB_UNKNOWN, **overrides}
    return await client.post(f"/api/devices/{uid}/heartbeat", json=payload)


async def get_pending_row(db_session, uid=UNKNOWN_UID) -> PendingDevice | None:
    return await db_session.scalar(
        select(PendingDevice).where(PendingDevice.device_uid == uid)
    )


# --- Mode: default off, toggle, permissions ---


async def test_disabled_by_default(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    # Unknown heartbeats are rejected and nothing is discovered.
    response = await heartbeat_unknown(client)
    assert response.status_code == 404

    body = await pending_list(client, token)
    assert body == {"devices": []}


async def test_toggle_format(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    body = await enable_autoconfig(client, token, enabled=True)
    assert body == {"enabled": True}
    body = await enable_autoconfig(client, token, enabled=True)  # idempotent
    assert body == {"enabled": True}
    body = await enable_autoconfig(client, token, enabled=False)
    assert body == {"enabled": False}


async def test_requires_manage_permission(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)

    no_token = await client.post("/api/devices/autoconfig", json={"enabled": True})
    assert no_token.status_code == 401

    # Mediator only holds devices.view: both endpoints must fail.
    forbidden_toggle = await client.post(
        "/api/devices/autoconfig",
        json={"enabled": True},
        headers=bearer(mediator_token),
    )
    assert forbidden_toggle.status_code == 403
    forbidden_pending = await client.get(
        "/api/devices/autoconfig/pending", headers=bearer(mediator_token)
    )
    assert forbidden_pending.status_code == 403


# --- Discovery while enabled ---


async def test_unknown_heartbeat_accepted_as_pending(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await enable_autoconfig(client, token)

    response = await heartbeat_unknown(client)
    assert response.status_code == 202
    body = response.json()
    assert body["device_uid"] == UNKNOWN_UID
    assert body["status"] == "pending_registration"
    assert body["last_seen"] is not None

    # 202 never creates an inventory row; only a pending discovery.
    assert await db_session.scalar(
        select(Device).where(Device.device_uid == UNKNOWN_UID)
    ) is None

    pending = await pending_list(client, token)
    assert len(pending["devices"]) == 1
    entry = pending["devices"][0]
    assert entry["device_uid"] == UNKNOWN_UID
    assert entry["ip_address"] == "10.15.1.164"
    assert entry["device_state"] == "active"
    assert entry["last_seen"]
    # payload is stored internally but never exposed.
    assert "payload" not in entry


async def test_pending_updates_without_duplicates(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await enable_autoconfig(client, token)

    first = await heartbeat_unknown(client)
    assert first.status_code == 202
    second = await heartbeat_unknown(client, ip_address="10.15.1.99")
    assert second.status_code == 202

    pending = await pending_list(client, token)
    assert len(pending["devices"]) == 1
    assert pending["devices"][0]["ip_address"] == "10.15.1.99"


async def test_pending_expires_without_heartbeats(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await enable_autoconfig(client, token)

    response = await heartbeat_unknown(client)
    assert response.status_code == 202

    # Simulate discovery age beyond the TTL: absence of heartbeats is the
    # only expiry criterion.
    row = await get_pending_row(db_session)
    row.last_seen = utc_now() - timedelta(seconds=60)
    await db_session.commit()

    pending = await pending_list(client, token)
    assert pending == {"devices": []}


async def test_registered_devices_never_pending(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await enable_autoconfig(client, token)

    # A registered device heartbeats normally while the mode is on.
    await register_device(client, token)
    response = await heartbeat_unknown(client)
    assert response.status_code == 200
    assert response.json()["status"] == "online"

    body = await pending_list(client, token)
    assert body == {"devices": []}


async def test_registering_a_discovered_device_removes_it_from_pending(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await enable_autoconfig(client, token)

    response = await heartbeat_unknown(client)
    assert response.status_code == 202
    pending = await pending_list(client, token)
    assert len(pending["devices"]) == 1

    # Definitive registration reuses the existing endpoint.
    await register_device(client, token)

    body = await pending_list(client, token)
    assert body == {"devices": []}
    assert await get_pending_row(db_session) is None

    # The next heartbeat is processed as a registered device.
    response = await heartbeat_unknown(client)
    assert response.status_code == 200
    assert response.json()["status"] == "online"


async def test_duplicate_registration_conflict(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await enable_autoconfig(client, token)
    await heartbeat_unknown(client)

    await register_device(client, token)
    response = await client.post(
        "/api/devices",
        json={
            "device_uid": UNKNOWN_UID,
            "name": "Otra",
            "type": "tablet",
            "ip_address": "10.15.1.164",
        },
        headers=bearer(token),
    )
    assert response.status_code == 409
    assert response.json()["code"] == "conflict"


# --- Disable ---


async def test_disable_stops_discovery_and_clears_pending(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    await enable_autoconfig(client, token)
    assert (await heartbeat_unknown(client)).status_code == 202
    assert len((await pending_list(client, token))["devices"]) == 1

    await enable_autoconfig(client, token, enabled=False)

    # The pending list is cleared and stays empty.
    body = await pending_list(client, token)
    assert body == {"devices": []}
    assert await get_pending_row(db_session) is None

    # Unknown heartbeats are rejected again.
    response = await heartbeat_unknown(client, uid="otro-tablet")
    assert response.status_code == 404

    # Registered devices are untouched and keep heartbeating normally.
    response = await heartbeat_unknown(client)
    assert response.status_code == 200
    assert response.json()["status"] == "online"
