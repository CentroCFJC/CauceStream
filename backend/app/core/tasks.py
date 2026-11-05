"""Periodic background tasks (plain asyncio, no external brokers).

Cauce must detect offline devices without waiting for a request, so a
lightweight sweep loop runs inside the application process.
"""

import asyncio
import logging

from app.core.config import get_settings
from app.core.database import AsyncSessionLocal
from app.services.device_service import DeviceService

logger = logging.getLogger(__name__)


async def sweep_offline_devices_once() -> int:
    """Run one offline-detection pass; returns the number of devices marked."""
    async with AsyncSessionLocal() as session:
        service = DeviceService(session)
        changed = await service.mark_stale_devices_offline()
        if changed:
            logger.info("Marked %d device(s) as offline", changed)
        # Pending autoconfig discoveries expire by heartbeat absence;
        # purge them in the same pass (no WebSocket disconnects needed).
        purged = await service.purge_stale_pending()
        if purged:
            logger.info("Purged %d stale autoconfig pending device(s)", purged)
        return changed


async def offline_devices_sweep_loop() -> None:
    """Periodically mark devices without recent heartbeats as offline."""
    interval = get_settings().DEVICE_SWEEP_INTERVAL_SECONDS
    while True:
        await asyncio.sleep(interval)
        try:
            await sweep_offline_devices_once()
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Offline device sweep failed; retrying next cycle")
