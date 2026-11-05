"""Password hashing (bcrypt) and JWT access tokens.

Token signing uses the local SECRET_KEY: Cauce operates inside the room's
LAN and must not depend on any external identity provider. This is the
only module that handles credentials material.
"""

from datetime import UTC, datetime, timedelta

import anyio
import bcrypt
import jwt

from app.core.config import get_settings


def _hash_sync(password: str, rounds: int) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=rounds)).decode("utf-8")


def _verify_sync(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:
        return False


async def hash_password(password: str) -> str:
    """Hash a plaintext password with bcrypt (runs off the event loop)."""
    rounds = get_settings().BCRYPT_ROUNDS
    return await anyio.to_thread.run_sync(_hash_sync, password, rounds)


async def verify_password(password: str, password_hash: str) -> bool:
    """Check a plaintext password against a stored bcrypt hash."""
    return await anyio.to_thread.run_sync(_verify_sync, password, password_hash)


def create_access_token(user_id: int) -> str:
    """Create a signed JWT for the given user id."""
    settings = get_settings()
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "iat": now,
        "exp": now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> int:
    """Validate a JWT and return the user id it was issued for.

    Raises jwt.InvalidTokenError (or a subclass) when invalid or expired.
    """
    settings = get_settings()
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
    return int(payload["sub"])
