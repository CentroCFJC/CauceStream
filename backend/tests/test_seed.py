"""Seed tests: fixed roles, initial permissions, bootstrap admin, idempotency.

Role and permission relationships are accessed through the repositories,
which eager-load them (async sessions cannot lazy-load).
"""

from sqlalchemy import func, select

from app.core.config import get_settings
from app.core.seed import (
    DEFAULT_ROLE_PERMISSIONS,
    PERMISSION_DEFINITIONS,
    seed_initial_data,
)
from app.models import Permission, Role, User
from app.repositories import RoleRepository, UserRepository


async def test_seed_creates_exactly_two_roles(db_session):
    roles = list(await db_session.scalars(select(Role)))
    assert {role.name for role in roles} == {"ADMINISTRADOR", "MEDIADOR"}


async def test_seed_permissions_catalogue(db_session):
    permissions = list(await db_session.scalars(select(Permission)))
    assert {p.name for p in permissions} == set(PERMISSION_DEFINITIONS)


async def test_seed_default_role_permissions(db_session):
    roles = RoleRepository(db_session)
    for role_name, expected in DEFAULT_ROLE_PERMISSIONS.items():
        role = await roles.get_by_name(role_name)
        assert {p.name for p in role.permissions} == set(expected)


async def test_seed_administrator_has_all_permissions(db_session):
    role = await RoleRepository(db_session).get_by_name("ADMINISTRADOR")
    assert {p.name for p in role.permissions} == set(PERMISSION_DEFINITIONS)


async def test_seed_mediator_permissions(db_session):
    role = await RoleRepository(db_session).get_by_name("MEDIADOR")
    assert {p.name for p in role.permissions} == {
        "devices.view",
        "experiences.view",
        "content.view",
        "schedules.view",
    }


async def test_seed_creates_bootstrap_admin(db_session):
    settings = get_settings()
    user = await UserRepository(db_session).get_by_email(settings.BOOTSTRAP_ADMIN_EMAIL)
    assert user is not None
    assert user.role.name == "ADMINISTRADOR"
    assert user.is_active is True


async def test_seed_is_idempotent(db_session):
    await seed_initial_data(db_session)

    roles_count = await db_session.scalar(select(func.count()).select_from(Role))
    permissions_count = await db_session.scalar(select(func.count()).select_from(Permission))
    users_count = await db_session.scalar(select(func.count()).select_from(User))

    assert roles_count == 2
    assert permissions_count == len(PERMISSION_DEFINITIONS)
    # Bootstrap admin only; the second run created no duplicates.
    assert users_count == 1
