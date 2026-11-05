"""User data access."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Role, User

# Role (and its permissions) are eager-loaded: authorization and
# serialization always need them.
_USER_LOAD_OPTIONS = (
    selectinload(User.role).selectinload(Role.permissions),
)


class UserRepository:
    """All user queries. No business rules here."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_id(self, user_id: int) -> User | None:
        return await self.session.scalar(
            select(User)
            .options(*_USER_LOAD_OPTIONS)
            .where(User.id == user_id)
            .execution_options(populate_existing=True)
        )

    async def get_by_email(self, email: str) -> User | None:
        return await self.session.scalar(
            select(User)
            .options(*_USER_LOAD_OPTIONS)
            .where(User.email == email)
            .execution_options(populate_existing=True)
        )

    async def list_all(self) -> list[User]:
        result = await self.session.scalars(
            select(User)
            .options(*_USER_LOAD_OPTIONS)
            .order_by(User.id)
            .execution_options(populate_existing=True)
        )
        return list(result)

    async def add(self, user: User) -> User:
        self.session.add(user)
        await self.session.flush()
        return user
