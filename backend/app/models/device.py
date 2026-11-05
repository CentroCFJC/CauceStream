"""Device ORM model."""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import JSON, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base

if TYPE_CHECKING:
    from app.models.device_event import DeviceEvent


class Device(Base):
    """Current state of a device.

    Identity is `device_uid` (stable); `ip_address`/`port` are dynamic
    client-reported connection data. `status` (online/offline) is determined
    by the server from heartbeat recency, never reported by the client.
    `device_state` (active/idle) is client-reported and generalizes screens
    and headless devices; it is independent of connectivity: an idle device
    can be online.
    """

    __tablename__ = "devices"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_uid: Mapped[str] = mapped_column(String(100), unique=True)
    name: Mapped[str] = mapped_column(String(100))
    type: Mapped[str] = mapped_column(String(50))
    ip_address: Mapped[str | None] = mapped_column(String(45), default=None)
    port: Mapped[int | None] = mapped_column(default=None)
    # MAC for Wake-on-LAN (server-side power-on of devices that are fully
    # off). Client-reported like the IP; also editable at registration.
    mac_address: Mapped[str | None] = mapped_column(String(17), default=None)
    status: Mapped[str] = mapped_column(
        String(20), default="offline", server_default="offline"
    )
    device_state: Mapped[str | None] = mapped_column(String(20), default=None)
    # Media the device reports playing: the Media.id as a string, or
    # "unknown" when the heartbeat did not report a valid media id.
    # Never inferred from app names or any other field.
    current_media: Mapped[str | None] = mapped_column(String(100), default=None)
    # Last known device-specific heartbeat attributes (battery, charging,
    # port, ...), merged per key. A missing attribute
    # in a heartbeat never clears a previously stored value.
    payload: Mapped[dict | None] = mapped_column(JSON, default=None)
    last_seen: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), default=None, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    events: Mapped[list["DeviceEvent"]] = relationship(
        back_populates="device", cascade="all, delete-orphan"
    )
