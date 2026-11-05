"""Role and permission business logic.

Roles themselves are fixed domain data (seeded); this service only exposes
consultation and permission assignment updates.
"""

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import BadRequestError, NotFoundError
from app.models import Permission, Role
from app.repositories import RoleRepository
from app.schemas.role import RolePermissionsUpdate


class RoleService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.roles = RoleRepository(session)

    async def list_roles(self) -> list[Role]:
        return await self.roles.list_roles()

    async def list_permissions(self) -> list[Permission]:
        return await self.roles.list_permissions()

    async def get_role(self, name: str) -> Role:
        return await self._require_role(name)

    async def set_role_permissions(
        self, name: str, payload: RolePermissionsUpdate
    ) -> Role:
        """Replace the role's permission set (duplicate names are ignored)."""
        role = await self._require_role(name)

        # Deduplicate while preserving order; empty payload clears the role.
        permission_names = list(dict.fromkeys(payload.permissions))

        known_permissions = {p.name: p for p in await self.roles.list_permissions()}
        unknown = [n for n in permission_names if n not in known_permissions]
        if unknown:
            raise BadRequestError(f"Unknown permissions: {', '.join(unknown)}")

        permission_ids = [known_permissions[n].id for n in permission_names]
        await self.roles.replace_role_permissions(role, permission_ids)
        await self.session.commit()
        return await self._require_role(name)

    async def _require_role(self, name: str) -> Role:
        role = await self.roles.get_by_name(name)
        if role is None:
            raise NotFoundError(f"Role {name} not found")
        return role
