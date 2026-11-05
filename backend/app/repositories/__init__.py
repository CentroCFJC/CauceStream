"""Data access layer.

Repositories encapsulate all SQL/ORM queries. Services depend on
repositories; endpoints never query the database directly.
"""

from app.repositories.assignment_repository import AssignmentRepository
from app.repositories.autoconfig_repository import AutoconfigRepository
from app.repositories.device_repository import DeviceRepository
from app.repositories.media_repository import MediaRepository
from app.repositories.role_repository import RoleRepository
from app.repositories.user_repository import UserRepository

__all__ = [
    "AssignmentRepository",
    "AutoconfigRepository",
    "DeviceRepository",
    "MediaRepository",
    "RoleRepository",
    "UserRepository",
]
