"""Authentication and access control tests."""

from app.core.security import create_access_token
from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    create_user_direct,
    login,
)


async def test_login_success(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    assert token


async def test_login_wrong_password(client, admin):
    response = await client.post(
        "/api/auth/login", json={"email": ADMIN_EMAIL, "password": "9999"}
    )
    assert response.status_code == 401
    assert response.json()["code"] == "not_authenticated"


async def test_login_unknown_email(client):
    response = await client.post(
        "/api/auth/login", json={"email": "nobody@example.com", "password": "0000"}
    )
    assert response.status_code == 401


async def test_login_inactive_user_rejected(client, db_session):
    await create_user_direct(db_session, "inactive@example.com", "1111", "MEDIADOR", is_active=False)
    response = await client.post(
        "/api/auth/login", json={"email": "inactive@example.com", "password": "1111"}
    )
    assert response.status_code == 403
    assert response.json()["code"] == "user_inactive"


async def test_unauthenticated_request_gets_401(client):
    response = await client.get("/api/users")
    assert response.status_code == 401
    assert response.json()["code"] == "not_authenticated"


async def test_invalid_token_gets_401(client):
    response = await client.get("/api/users", headers=bearer("not-a-real-token"))
    assert response.status_code == 401


async def test_valid_token_of_deleted_user_gets_401(client, db_session):
    user = await create_user_direct(db_session, "ghost@example.com", "1111", "MEDIADOR")
    token = create_access_token(user.id)
    await db_session.delete(user)
    await db_session.commit()

    response = await client.get("/api/users", headers=bearer(token))
    assert response.status_code == 401


async def test_inactive_user_token_rejected(client, db_session, admin):
    # A user logs in, is later deactivated, and the old token stops working.
    target = await create_user_direct(db_session, "later@example.com", "1111", "MEDIADOR")
    token = await login(client, "later@example.com", "1111")

    target.is_active = False
    await db_session.commit()

    response = await client.get("/api/roles", headers=bearer(token))
    assert response.status_code == 403
    assert response.json()["code"] == "user_inactive"


async def test_user_with_permission_gets_access(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.get("/api/users", headers=bearer(token))
    assert response.status_code == 200


async def test_user_without_permission_gets_403(client, mediator):
    token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    response = await client.get("/api/users", headers=bearer(token))
    assert response.status_code == 403
    assert response.json()["code"] == "permission_denied"
