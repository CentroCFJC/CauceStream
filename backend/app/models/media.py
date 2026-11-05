"""Media ORM model (RF-008, phase 1).

Metadata lives in PostgreSQL; the binaries live on the server disk under
the configured media directory. `storage_key` is a stable relative key
(the physical path is resolved from the current configuration), so files
survive restarts and container recreation when the volume is kept.
"""

from datetime import datetime

from sqlalchemy import BigInteger, DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class Media(Base):
    """An audiovisual medium: an uploaded image/video file or an
    external URL.

    - image/video: `storage_key` (relative), `mime_type` and `file_size`
      are set; `external_url` is null.
    - url: `external_url` is set; the file fields are null.
    """

    __tablename__ = "media"

    id: Mapped[int] = mapped_column(primary_key=True)
    # Display name: original filename (uploads) or the provided name.
    # Never used as a physical path.
    name: Mapped[str] = mapped_column(String(255))
    # image | video | url
    media_type: Mapped[str] = mapped_column(String(10))
    mime_type: Mapped[str | None] = mapped_column(String(100), default=None)
    # Size in bytes (uploads only).
    file_size: Mapped[int | None] = mapped_column(BigInteger, default=None)
    # Relative storage key, e.g. "images/<uuid>.png". Resolved against
    # the configured media directory; never an absolute path.
    storage_key: Mapped[str | None] = mapped_column(String(255), default=None)
    external_url: Mapped[str | None] = mapped_column(Text, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
