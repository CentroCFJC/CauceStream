"""SQLAlchemy ORM models.

Business models inherit from `app.core.database.Base`. Importing them here
registers every table on `Base.metadata` (used by Alembic autogenerate).
"""

from app.models.assignment import DeviceMediaAssignment
from app.models.autoconfig import AutoconfigState, PendingDevice
from app.models.device import Device
from app.models.device_event import DeviceEvent
from app.models.media import Media
from app.models.permission import Permission
from app.models.role import Role, RolePermission
from app.models.user import User

__all__ = [
    "DeviceMediaAssignment",
    "AutoconfigState",
    "PendingDevice",
    "Device",
    "DeviceEvent",
    "Media",
    "Permission",
    "Role",
    "RolePermission",
    "User",
]
