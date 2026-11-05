"""Autoconfig ORM models: the discovery mode flag and pending devices.

Both live in PostgreSQL (not in-memory) so every worker/instance of the
backend sees the same state. Pending devices are discovery data only:
they never become inventory rows until an administrator registers them
through the existing endpoint.
"""

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class AutoconfigState(Base):
    """Single-row table (id=1) holding the autoconfig mode flag.

    Off by default; the application resets it to off on startup so a
    restart never leaves discovery accidentally enabled.
    """

    __tablename__ = "autoconfig_state"

    id: Mapped[int] = mapped_column(primary_key=True)
    enabled: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False
    )


class PendingDevice(Base):
    """A device detected through heartbeats while autoconfig is enabled.

    Identified by `device_uid` (the OS-exposed device name, stored as
    received). Updated on every heartbeat, never duplicated. `payload`
    is kept internally for traceability but is NOT exposed to clients
    of the pending list.
    """

    __tablename__ = "autoconfig_pending_devices"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_uid: Mapped[str] = mapped_column(String(100), unique=True)
    ip_address: Mapped[str] = mapped_column(String(45))
    device_state: Mapped[str] = mapped_column(String(20))
    payload: Mapped[dict | None] = mapped_column(JSON, default=None)
    last_seen: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
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
