"""Authentication: verify credentials and resolve JWT tokens.

Authentication is separated from authorization: this service only
establishes WHO the caller is. WHAT the caller may do is decided by
permission checks (see app.core.authorization).
"""

import jwt

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotAuthenticatedError, UserInactiveError
from app.core.security import create_access_token, decode_access_token, verify_password
from app.models import User
from app.repositories import UserRepository


class AuthService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.users = UserRepository(session)

    async def login(self, email: str, password: str) -> str:
        """Verify credentials and return a signed access token."""
        user = await self.users.get_by_email(email)
        if user is None or not await verify_password(password, user.password_hash):
            raise NotAuthenticatedError("Invalid email or password")
        if not user.is_active:
            raise UserInactiveError("User account is disabled")
        return create_access_token(user.id)

    async def resolve_token(self, token: str) -> User:
        """Return the active user a token belongs to.

        Raises 401 for missing/invalid/expired tokens or deleted users, and
        403 when the account has been deactivated since the token was issued.
        """
        try:
            user_id = decode_access_token(token)
        except jwt.InvalidTokenError as exc:
            raise NotAuthenticatedError("Invalid or expired token") from exc
        user = await self.users.get_by_id(user_id)
        if user is None:
            raise NotAuthenticatedError("Invalid or expired token")
        if not user.is_active:
            raise UserInactiveError("User account is disabled")
        return user
