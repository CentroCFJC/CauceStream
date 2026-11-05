"""Autoconfig data access: mode flag and pending (discovered) devices."""

from datetime import datetime

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AutoconfigState, Device, PendingDevice

_STATE_ROW_ID = 1


class AutoconfigRepository:
    """All autoconfig queries. No business rules here."""

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    # --- Mode flag (single row, DB-backed for multi-worker state) ---

    async def is_enabled(self) -> bool:
        state = await self.session.get(AutoconfigState, _STATE_ROW_ID)
        return state.enabled if state is not None else False

    async def set_enabled(self, enabled: bool) -> None:
        """Create the single state row if missing, then update it."""
        state = await self.session.get(AutoconfigState, _STATE_ROW_ID)
        if state is None:
            state = AutoconfigState(id=_STATE_ROW_ID, enabled=enabled)
            self.session.add(state)
            try:
                await self.session.flush()
            except IntegrityError:
                # Concurrent creation of the row: adopt the existing one.
                await self.session.rollback()
                state = await self.session.get(AutoconfigState, _STATE_ROW_ID)
                assert state is not None
        state.enabled = enabled

    # --- Pending (discovered) devices ---

    async def get_pending_by_uid(self, device_uid: str) -> PendingDevice | None:
        return await self.session.scalar(
            select(PendingDevice).where(PendingDevice.device_uid == device_uid)
        )

    async def upsert_pending(
        self,
        *,
        device_uid: str,
        ip_address: str,
        device_state: str,
        payload: dict | None,
        last_seen: datetime,
    ) -> PendingDevice:
        """Insert or update the pending row for `device_uid`.

        Concurrent heartbeats of the same unknown device are resolved
        by the unique constraint: the loser rolls back to the savepoint
        and updates the winner's row.
        """
        existing = await self.get_pending_by_uid(device_uid)
        if existing is None:
            pending = PendingDevice(
                device_uid=device_uid,
                ip_address=ip_address,
                device_state=device_state,
                payload=payload,
                last_seen=last_seen,
            )
            try:
                async with self.session.begin_nested():
                    self.session.add(pending)
                    await self.session.flush()
                return pending
            except IntegrityError:
                # Lost the insert race: update the existing row instead.
                existing = await self.get_pending_by_uid(device_uid)

        existing.ip_address = ip_address
        existing.device_state = device_state
        existing.payload = payload
        existing.last_seen = last_seen
        return existing

    async def list_fresh(self, cutoff: datetime) -> list[PendingDevice]:
        """Pending devices with a heartbeat at or after `cutoff`."""
        result = await self.session.scalars(
            select(PendingDevice)
            .where(PendingDevice.last_seen >= cutoff)
            .order_by(PendingDevice.last_seen.desc())
        )
        return list(result)

    async def delete_pending(self, device_uid: str) -> int:
        result = await self.session.execute(
            delete(PendingDevice).where(PendingDevice.device_uid == device_uid)
        )
        return result.rowcount or 0

    async def delete_registered(self) -> int:
        """Drop pending rows whose uid is now a registered device."""
        result = await self.session.execute(
            delete(PendingDevice).where(
                PendingDevice.device_uid.in_(select(Device.device_uid))
            )
        )
        return result.rowcount or 0

    async def delete_expired(self, cutoff: datetime) -> int:
        """Drop pending devices without heartbeats within the window."""
        result = await self.session.execute(
            delete(PendingDevice).where(PendingDevice.last_seen < cutoff)
        )
        return result.rowcount or 0

    async def delete_all(self) -> int:
        result = await self.session.execute(delete(PendingDevice))
        return result.rowcount or 0
