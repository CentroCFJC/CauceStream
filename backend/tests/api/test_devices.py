"""Device registration, heartbeat, status and history tests."""

from datetime import timedelta
from urllib.parse import quote

from sqlalchemy import select

from app.models import Device, DeviceEvent
from app.services.device_service import DeviceService
from app.utils.time import utc_now
from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)

UID = "CAUCE-001"
HB = {
    "ip_address": "10.15.1.151",
    "device_state": "active",
    "payload": {"port": 8001},
}


async def register_device(client, token, uid=UID, ip="10.15.1.151", port=8001, name=None):
    response = await client.post(
        "/api/devices",
        json={
            "device_uid": uid,
            "name": name or f"Pantalla {uid}",
            "type": "screen",
            "ip_address": ip,
            "port": port,
        },
        headers=bearer(token),
    )
    assert response.status_code == 201, response.text
    return response.json()


async def heartbeat(client, uid=UID, **overrides):
    payload = {**HB, **overrides}
    return await client.post(f"/api/devices/{uid}/heartbeat", json=payload)


async def device_events(client, token, uid=UID):
    response = await client.get(f"/api/devices/{uid}/events", headers=bearer(token))
    assert response.status_code == 200
    return response.json()


async def get_device_row(db_session, uid=UID) -> Device:
    return await db_session.scalar(select(Device).where(Device.device_uid == uid))


# --- Registration ---


async def test_register_device(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    body = await register_device(client, token)

    assert body["device_uid"] == UID
    assert body["status"] == "offline"  # registration never marks online
    assert body["last_seen"] is None
    assert body["device_state"] is None
    assert body["current_media"] is None

    events = await device_events(client, token)
    assert [e["event_type"] for e in events] == ["device_registered"]


async def test_register_duplicate_uid_conflict(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await client.post(
        "/api/devices",
        json={
            "device_uid": UID,
            "name": "Otra",
            "type": "screen",
            "ip_address": "10.15.1.151",
            "port": 8001,
        },
        headers=bearer(token),
    )
    assert response.status_code == 409
    assert response.json()["code"] == "conflict"


async def test_device_uid_accepts_raw_device_names(client, admin, db_session):
    """Autoconfig registers devices with the OS-exposed name, spaces
    included, without normalization; the heartbeat path receives it
    URL-encoded."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    raw = "SALA PANTALLA 1"
    response = await client.post(
        "/api/devices",
        json={
            "device_uid": raw,
            "name": "Pantalla sala",
            "type": "screen",
            "ip_address": "10.15.1.151",
            "port": 8001,
        },
        headers=bearer(token),
    )
    assert response.status_code == 201, response.text

    response = await client.post(f"/api/devices/{quote(raw)}/heartbeat", json=HB)
    assert response.status_code == 200, response.text
    assert response.json()["device_uid"] == raw
    assert response.json()["status"] == "online"


async def test_register_requires_manage_permission(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    payload = {
        "device_uid": "CAUCE-XYZ",
        "name": "X",
        "type": "screen",
        "ip_address": "10.15.1.199",
        "port": 8001,
    }

    no_token = await client.post("/api/devices", json=payload)
    assert no_token.status_code == 401

    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    forbidden = await client.post(
        "/api/devices", json=payload, headers=bearer(mediator_token)
    )
    assert forbidden.status_code == 403  # mediator has devices.view only


async def test_mediator_can_list_devices(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    response = await client.get("/api/devices", headers=bearer(mediator_token))
    assert response.status_code == 200
    assert len(response.json()) == 1


# --- Heartbeats ---


async def test_heartbeat_unknown_device_404(client, db_session):
    response = await heartbeat(client, "CAUCE-GHOST")
    assert response.status_code == 404

    # No device was auto-created.
    assert await get_device_row(db_session, "CAUCE-GHOST") is None


async def test_first_heartbeat_marks_online(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await heartbeat(client)
    assert response.status_code == 200
    body = response.json()
    assert body["device_uid"] == UID
    assert body["status"] == "online"
    assert body["device_state"] == "active"
    assert body["current_media"] == "unknown"  # no media reported
    assert body["last_seen"] is not None

    events = await device_events(client, token)
    types = [e["event_type"] for e in events]
    assert "device_registered" in types
    assert "status_changed" in types  # offline -> online

    status_events = [e for e in events if e["event_type"] == "status_changed"]
    assert status_events[0]["previous_value"] == "offline"
    assert status_events[0]["new_value"] == "online"


async def test_identical_heartbeats_update_last_seen_without_new_events(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    await heartbeat(client)
    events_after_first = await device_events(client, token)

    # Simulate an older last_seen; a new identical heartbeat must refresh it.
    device = await get_device_row(db_session)
    device.last_seen = utc_now() - timedelta(minutes=5)
    await db_session.commit()

    await heartbeat(client)
    await heartbeat(client)

    events_after_third = await device_events(client, token)
    assert len(events_after_third) == len(events_after_first)  # no duplicates

    refreshed = await get_device_row(db_session)
    assert refreshed.status == "online"
    assert refreshed.last_seen > utc_now() - timedelta(minutes=5)


async def test_idle_device_stays_online(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await heartbeat(client, device_state="idle")
    assert response.status_code == 200
    assert response.json()["status"] == "online"
    assert response.json()["device_state"] == "idle"


async def test_device_state_change_event(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    await heartbeat(client, device_state="active")
    await heartbeat(client, device_state="idle")

    events = await device_events(client, token)
    state_events = [e for e in events if e["event_type"] == "device_state_changed"]
    # The first heartbeat establishes the initial state (None -> active);
    # the second one is the actual change (active -> idle).
    assert len(state_events) == 2
    assert state_events[0]["previous_value"] is None
    assert state_events[0]["new_value"] == "active"
    assert state_events[1]["previous_value"] == "active"
    assert state_events[1]["new_value"] == "idle"


async def test_media_change_event(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    await heartbeat(client, payload={"current_media": 5})
    await heartbeat(client, payload={"current_media": 7})

    events = await device_events(client, token)
    media_events = [e for e in events if e["event_type"] == "media_changed"]
    # None -> "5" (establishment), "5" -> "7" (change).
    assert len(media_events) == 2
    assert media_events[0]["previous_value"] is None
    assert media_events[0]["new_value"] == "5"
    assert media_events[1]["previous_value"] == "5"
    assert media_events[1]["new_value"] == "7"


async def test_media_reported_from_payload(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    # Without current_media the server stores "unknown" (explicit on
    # every heartbeat: absence is not "keep the previous one").
    response = await heartbeat(client, payload={"port": 8001})
    assert response.status_code == 200
    assert response.json()["current_media"] == "unknown"
    device = await get_device_row(db_session)
    assert device.current_media == "unknown"

    # A valid media id (int or digit string) is stored normalized.
    response = await heartbeat(client, payload={"current_media": 12})
    assert response.status_code == 200
    assert response.json()["current_media"] == "12"
    response = await heartbeat(client, payload={"current_media": "34"})
    assert response.json()["current_media"] == "34"

    # A non-identifying value is not a media: back to "unknown".
    response = await heartbeat(client, payload={"current_media": "nonsense"})
    assert response.status_code == 200
    assert response.json()["current_media"] == "unknown"


async def test_legacy_current_application_is_not_media(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    # An old client still sending the retired attribute must keep
    # working: 200, the value passes through as inert payload data and
    # is never interpreted as the played media.
    response = await heartbeat(
        client, payload={"port": 8001, "current_application": "cauce_stream"}
    )
    assert response.status_code == 200
    device = await get_device_row(db_session)
    assert device.current_media == "unknown"
    assert device.payload["current_application"] == "cauce_stream"


async def test_ip_and_port_change_events(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    await heartbeat(client)
    await heartbeat(client, ip_address="10.15.1.170", payload={"port": 8002})

    events = await device_events(client, token)
    ip_events = [e for e in events if e["event_type"] == "ip_changed"]
    port_events = [e for e in events if e["event_type"] == "port_changed"]
    assert len(ip_events) == 1
    assert ip_events[0]["previous_value"] == "10.15.1.151"
    assert ip_events[0]["new_value"] == "10.15.1.170"
    assert len(port_events) == 1
    assert port_events[0]["previous_value"] == "8001"
    assert port_events[0]["new_value"] == "8002"

    device = await get_device_row(db_session)
    assert device.ip_address == "10.15.1.170"
    assert device.port == 8002


# --- Offline detection (server-side) ---


async def test_sweep_marks_stale_device_offline_once(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    await heartbeat(client)

    # Simulate an old heartbeat.
    device = await get_device_row(db_session)
    device.last_seen = utc_now() - timedelta(seconds=60)
    await db_session.commit()

    changed = await DeviceService(db_session).mark_stale_devices_offline()
    assert changed == 1
    device = await get_device_row(db_session)
    assert device.status == "offline"

    events = await device_events(client, token)
    offline_events = [
        e
        for e in events
        if e["event_type"] == "status_changed" and e["new_value"] == "offline"
    ]
    assert len(offline_events) == 1

    # A second sweep emits no further events.
    changed_again = await DeviceService(db_session).mark_stale_devices_offline()
    assert changed_again == 0
    events = await device_events(client, token)
    assert len(events) == len(events)  # unchanged
    offline_events = [
        e
        for e in events
        if e["event_type"] == "status_changed" and e["new_value"] == "offline"
    ]
    assert len(offline_events) == 1


async def test_sweep_keeps_recent_devices_online(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    await heartbeat(client)

    changed = await DeviceService(db_session).mark_stale_devices_offline()
    assert changed == 0
    device = await get_device_row(db_session)
    assert device.status == "online"


async def test_recovery_after_offline_registers_new_status_change(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    await heartbeat(client)

    device = await get_device_row(db_session)
    device.last_seen = utc_now() - timedelta(seconds=60)
    await db_session.commit()
    await DeviceService(db_session).mark_stale_devices_offline()

    response = await heartbeat(client)
    assert response.status_code == 200
    assert response.json()["status"] == "online"

    events = await device_events(client, token)
    online_events = [
        e
        for e in events
        if e["event_type"] == "status_changed" and e["new_value"] == "online"
    ]
    assert len(online_events) == 2  # initial + recovery


# --- Validation ---


async def test_invalid_heartbeat_rejected_and_state_unchanged(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    for bad in [
        {**HB, "device_state": "off"},  # invalid device state
        {**HB, "ip_address": "999.999.999.999"},  # invalid IP
        {**HB, "payload": {"port": 0}},  # invalid port in payload
        {**HB, "payload": {"port": 70000}},  # out of range
        {**HB, "payload": {"battery_level": 101}},  # out of range
        {**HB, "payload": {"battery_level": -1}},  # out of range
        {**HB, "payload": {"is_charging": "not-a-bool"}},  # not a boolean
        {**HB, "payload": {"port": "http"}},  # not a port number
    ]:
        response = await client.post(f"/api/devices/{UID}/heartbeat", json=bad)
        assert response.status_code == 422, bad

    # Nothing was modified by the invalid attempts.
    device = await get_device_row(db_session)
    assert device.status == "offline"
    assert device.last_seen is None
    assert device.payload is None


# --- Device-specific payload ---


async def test_heartbeat_with_full_payload_is_persisted(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    payload = {
        "port": 8000,
        "battery_level": 78,
        "is_charging": False,
        "power_source": "battery",
        "custom_attribute": "reported-as-is",  # unknown attribute: allowed
    }
    response = await heartbeat(client, payload=payload)
    assert response.status_code == 200

    body = response.json()
    assert body["status"] == "online"
    assert body["payload"]["battery_level"] == 78
    assert body["payload"]["custom_attribute"] == "reported-as-is"

    device = await get_device_row(db_session)
    assert device.payload == payload
    assert device.port == 8000  # payload port syncs the inventory column


async def test_heartbeat_without_payload_keeps_previous_state(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await heartbeat(client, payload={"battery_level": 78})
    assert response.status_code == 200

    # Omitted payload: valid heartbeat, previous payload untouched.
    no_payload = {k: v for k, v in HB.items() if k != "payload"}
    response = await client.post(f"/api/devices/{UID}/heartbeat", json=no_payload)
    assert response.status_code == 200
    device = await get_device_row(db_session)
    # Absence never means the metric changed to false/zero/null.
    assert device.payload == {"battery_level": 78}


async def test_heartbeat_with_empty_payload(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await heartbeat(client, payload={})
    assert response.status_code == 200
    assert response.json()["status"] == "online"

    device = await get_device_row(db_session)
    assert device.payload is None  # nothing to store, no redundant write


async def test_battery_and_charging_reported(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await heartbeat(
        client, payload={"battery_level": 45, "is_charging": True}
    )
    assert response.status_code == 200

    device = await get_device_row(db_session)
    assert device.payload["battery_level"] == 45
    assert device.payload["is_charging"] is True

    shown = await client.get(f"/api/devices/{UID}", headers=bearer(token))
    assert shown.status_code == 200
    assert shown.json()["payload"] == {"battery_level": 45, "is_charging": True}


async def test_port_is_optional_per_device(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token, uid="CAUCE-PORT")
    await register_device(client, token, uid="CAUCE-NO-PORT", port=9000)

    with_port = await heartbeat(client, uid="CAUCE-PORT", payload={"port": 8123})
    no_port_body = {k: v for k, v in HB.items() if k != "payload"}
    without_port = await client.post(
        "/api/devices/CAUCE-NO-PORT/heartbeat", json=no_port_body
    )
    assert with_port.status_code == 200
    assert without_port.status_code == 200  # absent port is not an error

    reported = await get_device_row(db_session, "CAUCE-PORT")
    assert reported.port == 8123
    silent = await get_device_row(db_session, "CAUCE-NO-PORT")
    assert silent.port == 9000  # registration value kept, not zeroed


async def test_payload_change_is_reflected_in_stored_state(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    await heartbeat(client, payload={"battery_level": 90, "is_charging": True})
    await heartbeat(client, payload={"battery_level": 89, "is_charging": False})

    device = await get_device_row(db_session)
    assert device.payload == {"battery_level": 89, "is_charging": False}


async def test_identical_payload_produces_no_redundant_writes(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    await heartbeat(client, payload={"battery_level": 60})
    device = await get_device_row(db_session)
    stored_payload = device.payload

    await heartbeat(client, payload={"battery_level": 60})
    await heartbeat(client, payload={"battery_level": 60})

    device = await get_device_row(db_session)
    assert device.payload == stored_payload


async def test_payload_cannot_override_reserved_fields(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    for reserved in [
        {"device_uid": "CAUCE-EVIL"},
        {"status": "offline"},
        {"type": "vr"},
        {"name": "Hacked"},
        {"ip_address": "10.0.0.1"},
        {"device_state": "idle"},
        {"display_state": "asleep"},  # retired field name: still rejected
        {"current_app": "evil_app"},  # misleading alias: rejected
    ]:
        response = await heartbeat(client, payload=reserved)
        assert response.status_code == 422, reserved

    # No device state was modified by the rejected attempts.
    device = await get_device_row(db_session)
    assert device.device_uid == UID
    assert device.type == "screen"
    assert device.name == f"Pantalla {UID}"
    assert device.status == "offline"


# --- Deletion ---


async def test_delete_device_removes_it_and_its_history(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    await heartbeat(client)

    response = await client.delete(f"/api/devices/{UID}", headers=bearer(token))
    assert response.status_code == 204

    assert await get_device_row(db_session) is None
    # The change history went away with the device (cascade).
    events = await db_session.scalars(select(DeviceEvent))
    assert list(events) == []

    # The device is gone: queries 404 and heartbeats behave as unknown.
    response = await client.get(f"/api/devices/{UID}", headers=bearer(token))
    assert response.status_code == 404
    response = await heartbeat(client)
    assert response.status_code == 404


async def test_delete_unknown_device_404(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.delete("/api/devices/CAUCE-GHOST", headers=bearer(token))
    assert response.status_code == 404


async def test_delete_requires_manage_permission(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    no_token = await client.delete(f"/api/devices/{UID}")
    assert no_token.status_code == 401

    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    forbidden = await client.delete(
        f"/api/devices/{UID}", headers=bearer(mediator_token)
    )
    assert forbidden.status_code == 403  # mediator has devices.view only

    # The rejection did not delete anything.
    response = await client.get(f"/api/devices/{UID}", headers=bearer(token))
    assert response.status_code == 200


# --- Multiple devices ---


async def test_multiple_devices_are_independent(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token, uid="CAUCE-001")
    await register_device(client, token, uid="CAUCE-002")

    await heartbeat(client, uid="CAUCE-001", payload={"current_media": 1})
    await heartbeat(
        client, uid="CAUCE-002", payload={"current_media": 2}
    )

    response = await client.get("/api/devices/CAUCE-001", headers=bearer(token))
    assert response.json()["current_media"] == "1"

    response = await client.get("/api/devices/CAUCE-002", headers=bearer(token))
    assert response.json()["current_media"] == "2"

    events_1 = await device_events(client, token, uid="CAUCE-001")
    events_2 = await device_events(client, token, uid="CAUCE-002")
    # Registration already provided ip/port; the heartbeats reused the same
    # values, so no ip_changed/port_changed events exist.
    expected = {
        "device_registered",
        "status_changed",
        "device_state_changed",
        "media_changed",
    }
    assert {e["event_type"] for e in events_1} == expected
    assert {e["event_type"] for e in events_2} == expected
