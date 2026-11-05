"""Role and permission data access."""

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Permission, Role, RolePermission


class RoleRepository:
    """All role/permission queries. No business rules here."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_name(self, name: str) -> Role | None:
        return await self.session.scalar(
            select(Role)
            .options(selectinload(Role.permissions))
            .where(Role.name == name)
            .execution_options(populate_existing=True)
        )

    async def list_roles(self) -> list[Role]:
        result = await self.session.scalars(
            select(Role)
            .options(selectinload(Role.permissions))
            .order_by(Role.id)
            .execution_options(populate_existing=True)
        )
        return list(result)

    async def list_permissions(self) -> list[Permission]:
        result = await self.session.scalars(select(Permission).order_by(Permission.id))
        return list(result)

    async def permission_ids_for_role(self, role_id: int) -> list[int]:
        result = await self.session.scalars(
            select(RolePermission.permission_id).where(RolePermission.role_id == role_id)
        )
        return list(result)

    async def replace_role_permissions(
        self, role: Role, permission_ids: list[int]
    ) -> None:
        """Set the role's permissions to exactly the given ids (atomic replace)."""
        await self.session.execute(
            delete(RolePermission).where(RolePermission.role_id == role.id)
        )
        for permission_id in permission_ids:
            self.session.add(
                RolePermission(role_id=role.id, permission_id=permission_id)
            )
        await self.session.flush()
