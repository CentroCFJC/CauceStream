"""User management endpoints.

Queries require `users.view`. Mutations require the management permission
of the target role (`users.mediators.manage` / `users.admins.manage`),
enforced inside UserService so endpoints stay free of business rules.
"""

from fastapi import APIRouter, Depends, status

from app.api.deps import get_current_user, get_user_service, require_permission
from app.models.user import User
from app.schemas.user import UserCreate, UserRead, UserUpdate
from app.services.user_service import UserService

router = APIRouter(prefix="/users", tags=["users"])


@router.post(
    "",
    response_model=UserRead,
    status_code=status.HTTP_201_CREATED,
    summary="Create a user",
)
async def create_user(
    payload: UserCreate,
    actor: User = Depends(get_current_user),
    service: UserService = Depends(get_user_service),
) -> User:
    """Create a mediator or administrator. The caller needs the management
    permission of the target role; ordinary calls cannot create admins."""
    return await service.create_user(actor, payload)


@router.get(
    "",
    response_model=list[UserRead],
    summary="List users",
)
async def list_users(
    actor: User = Depends(require_permission("users.view")),
    service: UserService = Depends(get_user_service),
) -> list[User]:
    return await service.list_users()


@router.get(
    "/{user_id}",
    response_model=UserRead,
    summary="Get a user by id",
)
async def get_user(
    user_id: int,
    actor: User = Depends(require_permission("users.view")),
    service: UserService = Depends(get_user_service),
) -> User:
    return await service.get_user(user_id)


@router.patch(
    "/{user_id}",
    response_model=UserRead,
    summary="Update a user",
)
async def update_user(
    user_id: int,
    payload: UserUpdate,
    actor: User = Depends(get_current_user),
    service: UserService = Depends(get_user_service),
) -> User:
    """Update name, email, password or role of a user."""
    return await service.update_user(actor, user_id, payload)


@router.post(
    "/{user_id}/activate",
    response_model=UserRead,
    summary="Activate a user",
)
async def activate_user(
    user_id: int,
    actor: User = Depends(get_current_user),
    service: UserService = Depends(get_user_service),
) -> User:
    return await service.set_active(actor, user_id, active=True)


@router.post(
    "/{user_id}/deactivate",
    response_model=UserRead,
    summary="Deactivate a user (logical, never deleted)",
)
async def deactivate_user(
    user_id: int,
    actor: User = Depends(get_current_user),
    service: UserService = Depends(get_user_service),
) -> User:
    return await service.set_active(actor, user_id, active=False)
