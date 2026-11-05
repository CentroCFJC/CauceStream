"""WebSocket power controller: the original in-app method, kept as the
fallback for device types without a native server-side controller.

The command travels over the device's live playback WebSocket channel
(`power.command`) and the client app executes it: screen-on works on
Android via wake lock; screen-off needs the app provisioned as Device
Owner/Admin (client/docs/device_owner_setup.md).
"""

from __future__ import annotations

import logging

from app.core.ws import connection_manager
from app.models.device import Device
from app.power.base import DevicePowerController, PowerResult
from app.services.playback_service import build_power_command_message

logger = logging.getLogger(__name__)


class WebSocketPowerController(DevicePowerController):
    method = "websocket"
    requires_live_channel = True

    def __init__(self) -> None:
        self.last_command_id: int | None = None

    async def _send(self, device: Device, action: str) -> PowerResult:
        command_id = connection_manager.next_power_command_id(device.device_uid)
        message = build_power_command_message(device.device_uid, action, command_id)
        delivered = await connection_manager.send_power_command(device.device_uid, message)
        self.last_command_id = command_id if delivered else None
        return PowerResult(
            action=action,
            method=self.method,
            executed=delivered,
            success=delivered,
            detail="power.command enviado por WebSocket" if delivered
            else "sin canal WebSocket activo",
        )

    async def turn_on(self, device: Device) -> PowerResult:
        return await self._send(device, "on")

    async def turn_off(self, device: Device) -> PowerResult:
        return await self._send(device, "off")
