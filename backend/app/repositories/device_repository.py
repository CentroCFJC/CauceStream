"""Device and device-event data access."""

from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Device, DeviceEvent


class DeviceRepository:
    """All device queries. No business rules here."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_uid(self, device_uid: str, *, for_update: bool = False) -> Device | None:
        stmt = select(Device).where(Device.device_uid == device_uid)
        if for_update:
            # Serialize concurrent heartbeats of the same device; other
            # devices are unaffected.
            stmt = stmt.with_for_update()
        return await self.session.scalar(stmt)

    async def list_all(self) -> list[Device]:
        result = await self.session.scalars(select(Device).order_by(Device.id))
        return list(result)

    async def stale_online_devices(self, cutoff: datetime) -> list[Device]:
        """Devices currently online whose last heartbeat predates `cutoff`."""
        result = await self.session.scalars(
            select(Device).where(Device.status == "online", Device.last_seen < cutoff)
        )
        return list(result)

    async def add(self, device: Device) -> Device:
        self.session.add(device)
        await self.session.flush()
        return device

    async def delete(self, device: Device) -> None:
        await self.session.delete(device)

    async def list_events(self, device_id: int) -> list[DeviceEvent]:
        result = await self.session.scalars(
            select(DeviceEvent)
            .where(DeviceEvent.device_id == device_id)
            .order_by(DeviceEvent.id)
        )
        return list(result)
