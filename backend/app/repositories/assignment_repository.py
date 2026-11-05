"""Device-media assignment data access."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Device, DeviceMediaAssignment, Media


class AssignmentRepository:
    """All assignment queries. No business rules here."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_device_id(
        self, device_id: int
    ) -> DeviceMediaAssignment | None:
        return await self.session.scalar(
            select(DeviceMediaAssignment).where(
                DeviceMediaAssignment.device_id == device_id
            )
        )

    async def get_with_details(self, device_id: int):
        result = await self.session.execute(
            select(DeviceMediaAssignment, Device.device_uid, Media)
            .join(Device, Device.id == DeviceMediaAssignment.device_id)
            .join(Media, Media.id == DeviceMediaAssignment.media_id)
            .where(DeviceMediaAssignment.device_id == device_id)
        )
        return result.first()

    async def list_with_details(self) -> list:
        result = await self.session.execute(
            select(DeviceMediaAssignment, Device.device_uid, Media)
            .join(Device, Device.id == DeviceMediaAssignment.device_id)
            .join(Media, Media.id == DeviceMediaAssignment.media_id)
            .order_by(DeviceMediaAssignment.id)
        )
        return list(result)

    async def add(self, assignment: DeviceMediaAssignment) -> None:
        self.session.add(assignment)
