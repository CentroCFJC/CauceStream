"""Media data access."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Media


class MediaRepository:
    """All media queries. No business rules here."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def add(self, media: Media) -> Media:
        self.session.add(media)
        await self.session.flush()
        return media

    async def get_by_id(self, media_id: int) -> Media | None:
        return await self.session.get(Media, media_id)

    async def list_all(self, limit: int, offset: int) -> list[Media]:
        result = await self.session.scalars(
            select(Media)
            .order_by(Media.id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(result)

    async def delete(self, media: Media) -> None:
        await self.session.delete(media)
