"""User management business logic."""

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.authorization import ensure_permission
from app.core.exceptions import (
    BadRequestError,
    ConflictError,
    NotFoundError,
)
from app.core.security import hash_password
from app.models import User
from app.repositories import RoleRepository, UserRepository
from app.schemas.user import UserCreate, UserUpdate

# Mutating a user requires the management permission of the TARGET role.
# This keeps authorization permission-based: no role-name comparisons.
_MANAGE_PERMISSION_BY_ROLE: dict[str, str] = {
    "ADMINISTRADOR": "users.admins.manage",
    "MEDIADOR": "users.mediators.manage",
}


class UserService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.users = UserRepository(session)
        self.roles = RoleRepository(session)

    async def create_user(self, actor: User, payload: UserCreate) -> User:
        """Create a user. The actor needs the management permission for the
        target role, so ordinary creation cannot mint administrators."""
        ensure_permission(actor, _MANAGE_PERMISSION_BY_ROLE[payload.role])

        if await self.users.get_by_email(payload.email) is not None:
            raise ConflictError(f"Email {payload.email} is already registered")
        role = await self.roles.get_by_name(payload.role)
        if role is None:
            raise NotFoundError(f"Role {payload.role} not found")

        user = User(
            name=payload.name,
            email=str(payload.email),
            password_hash=await hash_password(payload.password),
            role_id=role.id,
            is_active=True,
        )
        try:
            await self.users.add(user)
            await self.session.commit()
        except IntegrityError as exc:
            await self.session.rollback()
            raise ConflictError(f"Email {payload.email} is already registered") from exc
        return await self._require_user(user.id)

    async def list_users(self) -> list[User]:
        return await self.users.list_all()

    async def get_user(self, user_id: int) -> User:
        return await self._require_user(user_id)

    async def update_user(self, actor: User, user_id: int, payload: UserUpdate) -> User:
        """Update editable fields. Changing (or editing a user of) a role
        requires the management permission of the resulting role."""
        user = await self._require_user(user_id)

        target_role = payload.role if payload.role is not None else user.role.name
        ensure_permission(actor, _MANAGE_PERMISSION_BY_ROLE[target_role])

        if payload.email is not None and payload.email != user.email:
            existing = await self.users.get_by_email(payload.email)
            if existing is not None:
                raise ConflictError(f"Email {payload.email} is already registered")
            user.email = str(payload.email)
        if payload.name is not None:
            user.name = payload.name
        if payload.password is not None:
            user.password_hash = await hash_password(payload.password)
        if payload.role is not None and payload.role != user.role.name:
            role = await self.roles.get_by_name(payload.role)
            if role is None:
                raise NotFoundError(f"Role {payload.role} not found")
            user.role_id = role.id

        try:
            await self.session.commit()
        except IntegrityError as exc:
            await self.session.rollback()
            raise ConflictError("Email is already registered") from exc
        return await self._require_user(user_id)

    async def set_active(self, actor: User, user_id: int, *, active: bool) -> User:
        """Activate or deactivate a user logically (is_active)."""
        user = await self._require_user(user_id)
        ensure_permission(actor, _MANAGE_PERMISSION_BY_ROLE[user.role.name])

        if not active and user.id == actor.id:
            raise BadRequestError("You cannot deactivate your own account")

        user.is_active = active
        await self.session.commit()
        return await self._require_user(user_id)

    async def _require_user(self, user_id: int) -> User:
        user = await self.users.get_by_id(user_id)
        if user is None:
            raise NotFoundError(f"User {user_id} not found")
        return user
