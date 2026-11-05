"""Media business logic (RF-008 phase 1): uploads, external URLs,
listing, file access and deletion.

PostgreSQL keeps the metadata; the configured media directory keeps the
binaries. File and record lifecycles are kept consistent: a failed DB
registration after a successful save removes the file; a failed write
never creates a record; deletion removes the file only after verifying
it belongs to the record (containment check) and only after the record
is gone.
"""

import logging

from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import storage
from app.core.config import get_settings
from app.core.exceptions import NotFoundError
from app.models import Media
from app.repositories import MediaRepository
from app.schemas.media import MediaUrlCreate

logger = logging.getLogger(__name__)

DEFAULT_LIST_LIMIT = 50
MAX_LIST_LIMIT = 200


class MediaService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.media = MediaRepository(session)

    @property
    def _media_dir(self):
        return get_settings().media_dir

    # --- Creation ---

    async def create_from_upload(
        self, media_type: str, name: str | None, file: UploadFile
    ) -> Media:
        """Validate and store an uploaded image/video, then register it.

        The original filename is kept only as metadata; the physical
        name is a unique storage key. If the DB write fails after the
        file was saved, the file is removed (no orphans pointing back).
        """
        mime, extension = storage.validate_upload(
            media_type, file.filename or "", file.content_type
        )
        settings = get_settings()
        storage_key = storage.storage_key_for(media_type, extension)

        size = await storage.save_stream(
            settings.media_dir, storage_key, file, settings.media_max_size_bytes
        )
        try:
            record = Media(
                name=(name or file.filename or storage_key).strip()[:255],
                media_type=media_type,
                mime_type=mime,
                file_size=size,
                storage_key=storage_key,
                external_url=None,
            )
            await self.media.add(record)
            await self.session.commit()
        except Exception:
            await self.session.rollback()
            storage.delete_file(settings.media_dir, storage_key)
            raise
        return record

    async def create_from_url(self, payload: MediaUrlCreate) -> Media:
        """Register an external URL with its metadata. The URL is never
        fetched or validated remotely."""
        record = Media(
            name=payload.name.strip()[:255],
            media_type="url",
            mime_type=payload.mime_type,
            file_size=None,
            storage_key=None,
            external_url=str(payload.url),
        )
        await self.media.add(record)
        await self.session.commit()
        return record

    # --- Queries ---

    async def list_media(self, limit: int, offset: int) -> list[Media]:
        limit = max(1, min(limit, MAX_LIST_LIMIT))
        offset = max(0, offset)
        return await self.media.list_all(limit, offset)

    async def get_media(self, media_id: int) -> Media:
        return await self._require_media(media_id)

    async def get_file_path(self, media_id: int):
        """Physical path of a stored binary (uploads only)."""
        media = await self._require_media(media_id)
        if not media.storage_key:
            raise NotFoundError(f"Media {media_id} has no stored file")
        path = storage.resolve_path(self._media_dir, media.storage_key)
        if not path.is_file():
            raise NotFoundError(f"File for media {media_id} is missing on disk")
        return path

    # --- Deletion ---

    async def delete_media(self, media_id: int) -> Media:
        """Delete the record, then its file. The file is only touched if
        its storage key resolves inside the media root (it belongs to
        this record); a file-level failure never resurrects the record."""
        media = await self._require_media(media_id)
        storage_key = media.storage_key
        await self.media.delete(media)
        await self.session.commit()

        if storage_key and not storage.delete_file(self._media_dir, storage_key):
            logger.warning(
                "Media %d deleted but its file was not found on disk", media_id
            )
        return media

    # --- Internals ---

    async def _require_media(self, media_id: int) -> Media:
        media = await self.media.get_by_id(media_id)
        if media is None:
            raise NotFoundError(f"Media {media_id} not found")
        return media
