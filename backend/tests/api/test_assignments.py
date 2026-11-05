"""Device-media assignment tests: assignment, reassignment, sync state
computation on assignment and heartbeat, validation and permissions."""

from sqlalchemy import select

from app.models import Device, DeviceMediaAssignment, Media
from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)

UID = "CAUCE-001"
HB = {"ip_address": "10.15.1.151", "device_state": "active"}


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


async def create_media(db_session, name="Loop sala", media_id=None) -> int:
    """Create a library medium straight through the ORM (test setup)."""
    media = Media(
        name=name,
        media_type="url",
        external_url="https://example.com/loop",
    )
    db_session.add(media)
    await db_session.commit()
    return media.id


async def heartbeat(client, uid=UID, **payload_overrides):
    payload = {"payload": {}, **HB}
    payload["payload"].update(payload_overrides)
    return await client.post(f"/api/devices/{uid}/heartbeat", json=payload)


async def assign(client, token, uid=UID, media_id=None):
    return await client.put(
        f"/api/devices/{uid}/assignment",
        json={"media_id": media_id},
        headers=bearer(token),
    )


async def assignments(client, token):
    response = await client.get("/api/assignments", headers=bearer(token))
    assert response.status_code == 200, response.text
    return response.json()


# --- Assignment ---


async def test_assign_media_creates_pending_assignment(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    response = await assign(client, token, media_id=media_id)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["device_uid"] == UID
    assert body["media_id"] == media_id
    assert body["media_name"] == "Loop sala"
    assert body["sync_status"] == "pending"  # device never reported media

    listing = await assignments(client, token)
    assert len(listing) == 1
    assert listing[0]["id"] == body["id"]
    assert listing[0]["sync_status"] == "pending"


async def test_reassign_updates_the_vigente_assignment(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    first = await create_media(db_session, name="Primero")
    second = await create_media(db_session, name="Segundo")

    created = (await assign(client, token, media_id=first)).json()
    reassigned = (await assign(client, token, media_id=second)).json()

    # One vigente assignment per device: the row is updated, not
    # duplicated.
    assert reassigned["id"] == created["id"]
    assert reassigned["media_id"] == second
    rows = list(
        await db_session.scalars(select(DeviceMediaAssignment))
    )
    assert len(rows) == 1
    assert rows[0].media_id == second
    listing = await assignments(client, token)
    assert len(listing) == 1


async def test_assign_validates_device_and_media_exist(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    unknown_device = await assign(client, token, uid="CAUCE-GHOST", media_id=media_id)
    assert unknown_device.status_code == 404

    unknown_media = await assign(client, token, media_id=media_id + 1000)
    assert unknown_media.status_code == 404


async def test_assign_immediately_synchronized_when_device_reports_it(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)

    # The device already reports playing this exact media id.
    response = await heartbeat(client, current_media=media_id)
    assert response.status_code == 200
    assert response.json()["current_media"] == str(media_id)

    assigned = (await assign(client, token, media_id=media_id)).json()
    assert assigned["sync_status"] == "synchronized"


# --- Sync state recomputed on heartbeats ---


async def test_heartbeat_synchronizes_the_assignment(client, admin, db_session):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)
    media_id = await create_media(db_session)
    await assign(client, token, media_id=media_id)

    # The device starts reporting the assigned media id.
    response = await heartbeat(client, current_media=media_id)
    assert response.status_code == 200
    listing = await assignments(client, token)
    assert listing[0]["sync_status"] == "synchronized"

    # ...and falls back to pending on a different id...
    await heartbeat(client, current_media=media_id + 1)
    listing = await assignments(client, token)
    assert listing[0]["sync_status"] == "pending"

    # ...or on "unknown" (no valid media reported).
    await heartbeat(client)
    listing = await assignments(client, token)
    assert listing[0]["sync_status"] == "pending"

    # Consistent persisted state, single assignment row.
    device = await db_session.scalar(select(Device).where(Device.device_uid == UID))
    assert device.current_media == "unknown"
    rows = list(await db_session.scalars(select(DeviceMediaAssignment)))
    assert len(rows) == 1
    assert rows[0].sync_status == "pending"


async def test_device_without_assignment_heartbeats_normally(
    client, admin, db_session
):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    await register_device(client, token)

    response = await heartbeat(client, current_media=3)
    assert response.status_code == 200
    assert response.json()["current_media"] == "3"

    rows = list(await db_session.scalars(select(DeviceMediaAssignment)))
    assert rows == []


# --- Permissions ---


async def test_assignment_permissions(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    mediator_token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)

    await register_device(client, token)
    no_token = await client.put(
        f"/api/devices/{UID}/assignment", json={"media_id": 1}
    )
    assert no_token.status_code == 401

    # Mediator holds content.view: listing is fine, assigning is not.
    listing = await client.get("/api/assignments", headers=bearer(mediator_token))
    assert listing.status_code == 200

    forbidden = await client.put(
        f"/api/devices/{UID}/assignment",
        json={"media_id": 1},
        headers=bearer(mediator_token),
    )
    assert forbidden.status_code == 403
