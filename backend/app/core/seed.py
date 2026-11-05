"""Initial data seeding (roles, permissions, bootstrap administrator).

Idempotent: safe to run on every startup. Creates anything that is missing
and never deletes or reverts data modified through the API. Default
role-permission assignments are applied only to a role that has no links
yet, so later permission updates made by an administrator survive restarts.
"""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import hash_password
from app.models import Permission, Role, RolePermission, User

ROLE_DEFINITIONS: dict[str, str] = {
    "ADMINISTRADOR": "Administra el sistema Cauce: usuarios, permisos, dispositivos y experiencias.",
    "MEDIADOR": "Opera las experiencias de la Sala Cauce segun sus permisos asignados.",
}

PERMISSION_DEFINITIONS: dict[str, str] = {
    "users.view": "Consultar usuarios.",
    "users.mediators.manage": "Crear, modificar, activar y desactivar mediadores.",
    "users.admins.manage": "Crear, modificar, activar y desactivar administradores.",
    "devices.view": "Consultar dispositivos y su estado.",
    "devices.manage": "Administrar dispositivos.",
    "devices.control": "Encender y apagar pantallas de dispositivos (entrada y salida de espera).",
    "experiences.view": "Consultar experiencias.",
    "experiences.manage": "Administrar experiencias.",
    "content.view": "Consultar contenido.",
    "content.manage": "Administrar y distribuir contenido.",
    "schedules.view": "Consultar programaciones.",
    "schedules.manage": "Administrar programaciones.",
    "roles.permissions.manage": "Consultar y modificar los permisos de los roles.",
}

DEFAULT_ROLE_PERMISSIONS: dict[str, list[str]] = {
    "ADMINISTRADOR": list(PERMISSION_DEFINITIONS),
    "MEDIADOR": [
        "devices.view",
        "experiences.view",
        "content.view",
        "schedules.view",
    ],
}


async def seed_initial_data(session: AsyncSession) -> None:
    """Ensure the fixed domain data exists. Never removes or reverts."""
    # Fixed roles.
    for name, description in ROLE_DEFINITIONS.items():
        if await session.scalar(select(Role).where(Role.name == name)) is None:
            session.add(Role(name=name, description=description))
    await session.flush()

    # Catalogued permissions.
    for name, description in PERMISSION_DEFINITIONS.items():
        if await session.scalar(select(Permission).where(Permission.name == name)) is None:
            session.add(Permission(name=name, description=description))
    await session.flush()

    # Default role-permission links, only for roles that have none yet.
    for role_name, permission_names in DEFAULT_ROLE_PERMISSIONS.items():
        role = await session.scalar(select(Role).where(Role.name == role_name))
        existing_links = await session.scalars(
            select(RolePermission.permission_id).where(RolePermission.role_id == role.id)
        )
        if list(existing_links):
            continue
        for permission_name in permission_names:
            permission = await session.scalar(
                select(Permission).where(Permission.name == permission_name)
            )
            session.add(RolePermission(role_id=role.id, permission_id=permission.id))
    await session.flush()

    # Bootstrap administrator, only when no ADMINISTRADOR exists.
    settings = get_settings()
    admin_role = await session.scalar(select(Role).where(Role.name == "ADMINISTRADOR"))
    has_admin = await session.scalar(
        select(User.id).where(User.role_id == admin_role.id).limit(1)
    )
    if has_admin is None:
        session.add(
            User(
                name=settings.BOOTSTRAP_ADMIN_NAME,
                email=settings.BOOTSTRAP_ADMIN_EMAIL,
                password_hash=await hash_password(settings.BOOTSTRAP_ADMIN_PASSWORD),
                role_id=admin_role.id,
                is_active=True,
            )
        )

    await session.commit()
