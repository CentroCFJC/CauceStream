"""Media schemas (API input/output, RF-008 phase 1)."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, model_validator

UploadMediaType = Literal["image", "video", "pdf"]
MediaType = Literal["image", "video", "url", "pdf"]


class MediaUrlCreate(BaseModel):
    """Payload for POST /api/media/urls (external URL registration).

    The backend stores the address and its metadata; it never fetches or
    follows the URL.
    """

    name: str = Field(min_length=1, max_length=255)
    url: HttpUrl
    mime_type: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def _require_http_scheme(self) -> "MediaUrlCreate":
        if self.url.scheme not in ("http", "https"):
            raise ValueError("Only http/https URLs are accepted")
        return self


class MediaRead(BaseModel):
    """Media representation (metadata; binaries are served by
    GET /api/media/{id}/file)."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    media_type: MediaType
    mime_type: str | None
    file_size: int | None
    storage_key: str | None
    external_url: str | None
    created_at: datetime
    updated_at: datetime
