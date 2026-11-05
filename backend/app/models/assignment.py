"""Device-media assignment ORM model.

One vigente assignment per device (MVP rule), enforced by the unique
constraint on `device_id`: assigning another media UPDATES the existing
row instead of creating concurrent active assignments. `sync_status`
compares the assigned media with what the device reports playing and is
recomputed on every assignment and heartbeat.
"""

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base

SYNC_SYNCHRONIZED = "synchronized"
SYNC_PENDING = "pending"


class DeviceMediaAssignment(Base):
    """The media the administration assigned to a device, plus its
    synchronization state against the media the device reports playing."""

    __tablename__ = "device_media_assignments"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    media_id: Mapped[int] = mapped_column(
        ForeignKey("media.id", ondelete="CASCADE"), nullable=False
    )
    # synchronized: the device reports playing the assigned media id.
    # pending: anything else (unknown, different id, never reported).
    sync_status: Mapped[str] = mapped_column(String(20), nullable=False)
    # Monotonic per device: incremented on every assignment change so
    # clients can tell stale commands from the latest desired state.
    revision: Mapped[int] = mapped_column(default=1, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
