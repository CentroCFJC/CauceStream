"""Shared FastAPI dependencies: database session, services and authorization."""

from collections.abc import AsyncGenerator

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.authorization import ensure_permission
from app.core.database import AsyncSessionLocal
from app.core.exceptions import NotAuthenticatedError
from app.models.user import User
from app.power import get_power_registry
from app.power.base import PowerControllerRegistry
from app.services.assignment_service import AssignmentService
from app.services.auth_service import AuthService
from app.services.device_service import DeviceService
from app.services.media_service import MediaService
from app.services.role_service import RoleService
from app.services.room_power_service import RoomPowerService
from app.services.user_service import UserService


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """Yield an async database session for the duration of a request.

    Business endpoints depend on this; repositories receive the session
    so no SQL ends up in the API layer.
    """
    async with AsyncSessionLocal() as session:
        yield session


def get_user_service(session: AsyncSession = Depends(get_session)) -> UserService:
    return UserService(session)


def get_role_service(session: AsyncSession = Depends(get_session)) -> RoleService:
    return RoleService(session)


def get_auth_service(session: AsyncSession = Depends(get_session)) -> AuthService:
    return AuthService(session)


def get_device_service(session: AsyncSession = Depends(get_session)) -> DeviceService:
    return DeviceService(session)


def get_media_service(session: AsyncSession = Depends(get_session)) -> MediaService:
    return MediaService(session)


def get_assignment_service(
    session: AsyncSession = Depends(get_session),
) -> AssignmentService:
    return AssignmentService(session)


def get_room_power_service() -> RoomPowerService:
    """Stateless: no session, the task history lives in Task Scheduler."""
    return RoomPowerService()


def get_power_controller_registry() -> PowerControllerRegistry:
    """Shared registry: device.type -> power controller (adb, websocket...)."""
    return get_power_registry()


_bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    service: AuthService = Depends(get_auth_service),
) -> User:
    """Resolve the caller from the Authorization bearer token.

    This is the single integration point with the authentication layer:
    401 when credentials are missing or invalid, 403 when the account is
    disabled.
    """
    if credentials is None:
        raise NotAuthenticatedError("Not authenticated")
    return await service.resolve_token(credentials.credentials)


async def get_optional_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    service: AuthService = Depends(get_auth_service),
) -> User | None:
    """Resolve the caller only when an Authorization header is present.

    Invalid tokens still raise 401 (never silently downgraded); a
    missing token simply means "no user", letting dual-auth endpoints
    fall back to the device key.
    """
    if credentials is None:
        return None
    return await service.resolve_token(credentials.credentials)


def require_permission(permission: str):
    """Dependency factory: allow access only to users holding `permission`."""

    async def dependency(user: User = Depends(get_current_user)) -> User:
        ensure_permission(user, permission)
        return user

    return dependency
