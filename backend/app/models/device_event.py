"""Device change-history ORM model and event types.

Only relevant changes are stored (never one row per heartbeat). Values are
stored as text so every event type shares the same shape.
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base

if TYPE_CHECKING:
    from app.models.device import Device

EVENT_DEVICE_REGISTERED = "device_registered"
EVENT_STATUS_CHANGED = "status_changed"
EVENT_DEVICE_STATE_CHANGED = "device_state_changed"
EVENT_MEDIA_CHANGED = "media_changed"
EVENT_IP_CHANGED = "ip_changed"
EVENT_PORT_CHANGED = "port_changed"
EVENT_MAC_CHANGED = "mac_changed"
EVENT_NAME_CHANGED = "name_changed"
EVENT_TYPE_CHANGED = "type_changed"


class DeviceEvent(Base):
    """A relevant change in a device's state (previous -> new value)."""

    __tablename__ = "device_events"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[int] = mapped_column(
        ForeignKey("devices.id", ondelete="CASCADE"), index=True
    )
    event_type: Mapped[str] = mapped_column(String(50))
    previous_value: Mapped[str | None] = mapped_column(Text, default=None)
    new_value: Mapped[str | None] = mapped_column(Text, default=None)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    device: Mapped["Device"] = relationship(back_populates="events")
