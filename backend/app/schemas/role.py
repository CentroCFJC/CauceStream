"""Role and permission schemas (API input/output)."""

from pydantic import BaseModel, ConfigDict, Field


class PermissionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: str | None


class RoleRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: str | None
    permissions: list[PermissionRead]


class RolePermissionsUpdate(BaseModel):
    """Payload for PUT /api/roles/{role_name}/permissions.

    The list replaces the role's permissions entirely; duplicate names in
    the payload are ignored.
    """

    permissions: list[str] = Field(default_factory=list)
