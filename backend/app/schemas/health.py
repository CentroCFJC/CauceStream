"""Health check schemas."""

from typing import Literal

from pydantic import BaseModel


class HealthResponse(BaseModel):
    """Response of GET /api/health."""

    status: Literal["ok"] = "ok"
