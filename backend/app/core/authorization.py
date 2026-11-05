"""Permission-based authorization helpers.

Authorization checks are always expressed as permissions, never as role-name
comparisons. Roles only determine which permissions a user holds.
"""

from app.core.exceptions import PermissionDeniedError
from app.models.user import User


def user_permission_names(user: User) -> set[str]:
    """Return the set of permission names granted to the user's role."""
    return {permission.name for permission in user.role.permissions}


def ensure_permission(user: User, permission: str) -> None:
    """Raise PermissionDeniedError unless the user's role holds `permission`."""
    if permission not in user_permission_names(user):
        raise PermissionDeniedError(f"Missing permission: {permission}")
