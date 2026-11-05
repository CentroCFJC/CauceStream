"""Role and permission consultation/assignment endpoints.

Roles are fixed domain data (no CRUD). Queries are gated by `users.view`
(reference data for user management); modifying a role's permissions
requires `roles.permissions.manage`.
"""

from fastapi import APIRouter, Depends

from app.api.deps import get_role_service, require_permission
from app.models.permission import Permission
from app.models.role import Role
from app.models.user import User
from app.schemas.role import PermissionRead, RolePermissionsUpdate, RoleRead
from app.services.role_service import RoleService

router = APIRouter(tags=["roles"])


@router.get(
    "/roles",
    response_model=list[RoleRead],
    summary="List roles",
)
async def list_roles(
    actor: User = Depends(require_permission("users.view")),
    service: RoleService = Depends(get_role_service),
) -> list[Role]:
    return await service.list_roles()


@router.get(
    "/permissions",
    response_model=list[PermissionRead],
    summary="List all catalogued permissions",
)
async def list_permissions(
    actor: User = Depends(require_permission("users.view")),
    service: RoleService = Depends(get_role_service),
) -> list[Permission]:
    return await service.list_permissions()


@router.get(
    "/roles/{role_name}/permissions",
    response_model=RoleRead,
    summary="Get the permissions assigned to a role",
)
async def get_role_permissions(
    role_name: str,
    actor: User = Depends(require_permission("users.view")),
    service: RoleService = Depends(get_role_service),
) -> Role:
    return await service.get_role(role_name)


@router.put(
    "/roles/{role_name}/permissions",
    response_model=RoleRead,
    summary="Replace the permissions assigned to a role",
)
async def update_role_permissions(
    role_name: str,
    payload: RolePermissionsUpdate,
    actor: User = Depends(require_permission("roles.permissions.manage")),
    service: RoleService = Depends(get_role_service),
) -> Role:
    """Replace the role's permission set. Duplicate names are ignored;
    unknown names are rejected."""
    return await service.set_role_permissions(role_name, payload)
