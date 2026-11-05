"""User management endpoint tests."""

from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)


async def test_admin_creates_mediator(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.post(
        "/api/users",
        json={
            "name": "Nuevo Mediador",
            "email": "new.mediator@example.com",
            "password": "6789",
            "role": "MEDIADOR",
        },
        headers=bearer(token),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["email"] == "new.mediator@example.com"
    assert body["role"]["name"] == "MEDIADOR"
    assert body["is_active"] is True
    assert "password_hash" not in body


async def test_mediator_cannot_create_users(client, mediator):
    token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    response = await client.post(
        "/api/users",
        json={
            "name": "Another",
            "email": "another@example.com",
            "password": "6789",
            "role": "MEDIADOR",
        },
        headers=bearer(token),
    )
    assert response.status_code == 403


async def test_admin_creates_administrator(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.post(
        "/api/users",
        json={
            "name": "Second Admin",
            "email": "admin2@example.com",
            "password": "6789",
            "role": "ADMINISTRADOR",
        },
        headers=bearer(token),
    )
    assert response.status_code == 201
    assert response.json()["role"]["name"] == "ADMINISTRADOR"


async def test_duplicate_email_rejected(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.post(
        "/api/users",
        json={
            "name": "Duplicated",
            "email": MEDIATOR_EMAIL,
            "password": "6789",
            "role": "MEDIADOR",
        },
        headers=bearer(token),
    )
    assert response.status_code == 409
    assert response.json()["code"] == "conflict"


async def test_list_users(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.get("/api/users", headers=bearer(token))
    assert response.status_code == 200
    emails = {user["email"] for user in response.json()}
    assert {ADMIN_EMAIL, MEDIATOR_EMAIL} <= emails
    assert all("password_hash" not in user for user in response.json())


async def test_get_user_by_id(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.get(f"/api/users/{mediator.id}", headers=bearer(token))
    assert response.status_code == 200
    assert response.json()["email"] == MEDIATOR_EMAIL


async def test_get_unknown_user_404(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.get("/api/users/9999", headers=bearer(token))
    assert response.status_code == 404


async def test_update_user_name_and_email(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.patch(
        f"/api/users/{mediator.id}",
        json={"name": "Renamed", "email": "renamed@example.com"},
        headers=bearer(token),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Renamed"
    assert body["email"] == "renamed@example.com"
    assert "password_hash" not in body


async def test_update_password_allows_new_login(client, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.patch(
        f"/api/users/{mediator.id}",
        json={"password": "2222"},
        headers=bearer(token),
    )
    assert response.status_code == 200

    new_token = await login(client, MEDIATOR_EMAIL, "2222")
    assert new_token


async def test_mediator_cannot_update_admin(client, admin, mediator):
    token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    response = await client.patch(
        f"/api/users/{admin.id}",
        json={"name": "Hacked"},
        headers=bearer(token),
    )
    assert response.status_code == 403


async def test_deactivate_and_reactivate_user(client, db_session, admin, mediator):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await client.post(f"/api/users/{mediator.id}/deactivate", headers=bearer(token))
    assert response.status_code == 200
    assert response.json()["is_active"] is False

    # The deactivated user can no longer log in.
    login_response = await client.post(
        "/api/auth/login", json={"email": MEDIATOR_EMAIL, "password": MEDIATOR_PASSWORD}
    )
    assert login_response.status_code == 403

    response = await client.post(f"/api/users/{mediator.id}/activate", headers=bearer(token))
    assert response.status_code == 200
    assert response.json()["is_active"] is True

    reactivated = await client.post(
        "/api/auth/login", json={"email": MEDIATOR_EMAIL, "password": MEDIATOR_PASSWORD}
    )
    assert reactivated.status_code == 200


async def test_mediator_cannot_deactivate(client, admin, mediator):
    token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    response = await client.post(f"/api/users/{admin.id}/deactivate", headers=bearer(token))
    assert response.status_code == 403


async def test_cannot_deactivate_self(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.post(f"/api/users/{admin.id}/deactivate", headers=bearer(token))
    assert response.status_code == 400
    assert response.json()["code"] == "bad_request"


async def test_pin_format_is_enforced(client, admin):
    """Passwords must be exactly 4 numeric digits."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    for bad_pin in ["123", "12345", "12a4", "abcd", ""]:
        response = await client.post(
            "/api/users",
            json={
                "name": "Bad Pin",
                "email": "badpin@example.com",
                "password": bad_pin,
                "role": "MEDIADOR",
            },
            headers=bearer(token),
        )
        assert response.status_code == 422, bad_pin


async def test_pin_with_leading_zeros(client, admin):
    """A PIN like 0042 keeps its leading zeros."""
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.post(
        "/api/users",
        json={
            "name": "Leading Zeros",
            "email": "zeros@example.com",
            "password": "0042",
            "role": "MEDIADOR",
        },
        headers=bearer(token),
    )
    assert response.status_code == 201

    new_token = await login(client, "zeros@example.com", "0042")
    assert new_token
