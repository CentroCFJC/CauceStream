"""User schemas (API input/output)."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.schemas.common import Pin

# Fixed domain roles; no role CRUD exists.
RoleName = Literal["ADMINISTRADOR", "MEDIADOR"]


class UserCreate(BaseModel):
    """Payload for POST /api/users."""

    name: str = Field(min_length=1, max_length=100)
    email: EmailStr
    password: Pin
    role: RoleName


class UserUpdate(BaseModel):
    """Payload for PATCH /api/users/{id}. All fields optional."""

    name: str | None = Field(default=None, min_length=1, max_length=100)
    email: EmailStr | None = None
    password: Pin | None = None
    role: RoleName | None = None


class RoleBrief(BaseModel):
    """Role reference embedded in user responses."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    description: str | None


class UserRead(BaseModel):
    """User representation. `password_hash` is never exposed."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: str
    role: RoleBrief
    is_active: bool
    created_at: datetime
    updated_at: datetime
