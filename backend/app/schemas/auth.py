"""Authentication schemas."""

from pydantic import BaseModel, EmailStr

from app.schemas.common import Pin


class LoginRequest(BaseModel):
    """Payload for POST /api/auth/login."""

    email: EmailStr
    password: Pin


class TokenResponse(BaseModel):
    """JWT access token response."""

    access_token: str
    token_type: str = "bearer"
