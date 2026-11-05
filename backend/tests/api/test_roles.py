"""Role and permission endpoint tests."""

from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)

MEDIATOR_DEFAULT_PERMISSIONS = {
    "devices.view",
    "experiences.view",
    "content.view",
    "schedules.view",
}


async def test_list_roles(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.get("/api/roles", headers=bearer(token))
    assert response.status_code == 200
    assert {role["name"] for role in response.json()} == {"ADMINISTRADOR", "MEDIADOR"}


async def test_list_permissions(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.get("/api/permissions", headers=bearer(token))
    assert response.status_code == 200
    names = {p["name"] for p in response.json()}
    assert {
        "users.view",
        "users.mediators.manage",
        "users.admins.manage",
        "roles.permissions.manage",
    } <= names


async def test_get_role_permissions(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.get("/api/roles/MEDIADOR/permissions", headers=bearer(token))
    assert response.status_code == 200
    assert {p["name"] for p in response.json()["permissions"]} == MEDIATOR_DEFAULT_PERMISSIONS


async def test_update_role_permissions(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    # Remove schedules.view from MEDIADOR.
    response = await client.put(
        "/api/roles/MEDIADOR/permissions",
        json={"permissions": ["devices.view", "experiences.view", "content.view"]},
        headers=bearer(token),
    )
    assert response.status_code == 200
    assert {p["name"] for p in response.json()["permissions"]} == {
        "devices.view",
        "experiences.view",
        "content.view",
    }

    # Restore the default set.
    response = await client.put(
        "/api/roles/MEDIADOR/permissions",
        json={"permissions": sorted(MEDIATOR_DEFAULT_PERMISSIONS)},
        headers=bearer(token),
    )
    assert response.status_code == 200
    assert {p["name"] for p in response.json()["permissions"]} == MEDIATOR_DEFAULT_PERMISSIONS


async def test_update_role_permissions_rejects_unknown_names(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.put(
        "/api/roles/MEDIADOR/permissions",
        json={"permissions": ["devices.view", "no.such.permission"]},
        headers=bearer(token),
    )
    assert response.status_code == 400
    assert "no.such.permission" in response.json()["detail"]


async def test_update_role_permissions_requires_permission(client, mediator):
    token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)
    response = await client.put(
        "/api/roles/MEDIADOR/permissions",
        json={"permissions": ["devices.view"]},
        headers=bearer(token),
    )
    assert response.status_code == 403


async def test_update_unknown_role_404(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.put(
        "/api/roles/NOEXISTE/permissions",
        json={"permissions": ["devices.view"]},
        headers=bearer(token),
    )
    assert response.status_code == 404


async def test_duplicate_permission_names_in_payload_are_ignored(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
    response = await client.put(
        "/api/roles/MEDIADOR/permissions",
        json={"permissions": ["devices.view", "devices.view", "content.view"]},
        headers=bearer(token),
    )
    assert response.status_code == 200
    assert {p["name"] for p in response.json()["permissions"]} == {
        "devices.view",
        "content.view",
    }
