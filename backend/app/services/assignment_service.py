"""Device-media assignment business logic.

The synchronization state is THE single comparison between the media the
administration assigned and the media the device reports playing
(`Device.current_media`): equal ids -> synchronized; anything else
(unknown, different id, never reported) -> pending. It says nothing
about successful playback: the current protocol only reports media
identifiers.
"""

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError
from app.core.ws import connection_manager
from app.models import Device, DeviceMediaAssignment, Media
from app.repositories import AssignmentRepository, DeviceRepository, MediaRepository
from app.schemas.assignment import AssignmentRead, AssignmentSetResult
from app.services.playback_service import build_command_message


def compute_sync_status(reported_media: str | None, media_id: int) -> str:
    """Central comparison used by assignments AND heartbeats."""
    return "synchronized" if reported_media == str(media_id) else "pending"


class AssignmentService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.assignments = AssignmentRepository(session)
        self.devices = DeviceRepository(session)
        self.media = MediaRepository(session)

    async def assign(self, device_uid: str, media_id: int) -> AssignmentSetResult:
        """Assign a media to a device as the single vigente assignment.

        Reassigning UPDATES the existing row (unique device_id) and
        increments its per-device revision, instead of creating
        concurrent active assignments. The sync state is computed
        against what the device currently reports, using the same central
        rule as heartbeats. The change is persisted FIRST; the
        `playback.command` notification is sent only after the commit, so
        a lost connection never loses the assignment (the device gets it
        via `playback.sync` on reconnect) and an in-flight command can
        never represent an older state than the newest commit.

        The result carries `delivered`: True only when the command was
        written to the device's live socket without error. Never a
        receipt/execution confirmation: that remains exclusive to
        heartbeats (`sync_status`).
        """
        device = await self.devices.get_by_uid(device_uid, for_update=True)
        if device is None:
            raise NotFoundError(f"Device {device_uid} not found")
        media = await self.media.get_by_id(media_id)
        if media is None:
            raise NotFoundError(f"Media {media_id} not found")

        sync_status = compute_sync_status(device.current_media, media_id)
        existing = await self.assignments.get_by_device_id(device.id)
        if existing is None:
            assignment = DeviceMediaAssignment(
                device_id=device.id,
                media_id=media_id,
                sync_status=sync_status,
                revision=1,
            )
            try:
                async with self.session.begin_nested():
                    await self.assignments.add(assignment)
                    await self.session.flush()
            except IntegrityError:
                # Concurrent assignment for the same device: adopt and
                # update the existing vigente row.
                existing = await self.assignments.get_by_device_id(device.id)
                existing.media_id = media_id
                existing.sync_status = sync_status
                existing.revision += 1
        else:
            existing.media_id = media_id
            existing.sync_status = sync_status
            existing.revision += 1

        await self.session.commit()
        row = await self.assignments.get_with_details(device.id)
        # Notify AFTER the transaction is confirmed. Sending never marks
        # the assignment as played and never raises into the request.
        # delivered: send only, no receipt/execution guarantee.
        delivered = await connection_manager.send_command(
            device_uid, build_command_message(device_uid, row)
        )
        read = self._to_read(row)
        return AssignmentSetResult(**read.model_dump(), delivered=delivered)

    async def list_all(self) -> list[AssignmentRead]:
        """All vigente assignments with their sync states (single joined
        query; no per-device SQL)."""
        return [self._to_read(row) for row in await self.assignments.list_with_details()]

    @staticmethod
    def _to_read(row) -> AssignmentRead:
        assignment, device_uid, media = row
        return AssignmentRead(
            id=assignment.id,
            device_id=assignment.device_id,
            device_uid=device_uid,
            media_id=assignment.media_id,
            media_name=media.name,
            sync_status=assignment.sync_status,
            revision=assignment.revision,
            created_at=assignment.created_at,
            updated_at=assignment.updated_at,
        )
