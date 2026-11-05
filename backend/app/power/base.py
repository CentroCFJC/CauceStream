"""Per-device power control: one controller per device type.

The server executes power actions itself (it runs natively on the Windows
server), targeting the IP the device last reported in its heartbeat -
instead of depending on the client app's permissions, which Android denies
for screen-off. Each device `type` maps to a DevicePowerController; types
without a native controller fall back to the device's live WebSocket
channel (the original in-app method).

Common concerns (validating the target IP, logging, the global deadline)
live here and in the endpoint; each controller only implements
turn_on/turn_off for its device type.
"""

from __future__ import annotations

import ipaddress
import logging
from abc import ABC, abstractmethod
from collections.abc import Callable
from dataclasses import dataclass

from app.models.device import Device

logger = logging.getLogger(__name__)


class PowerTargetError(Exception):
    """The device cannot be targeted safely (missing/invalid/public IP)."""


@dataclass(frozen=True)
class PowerResult:
    """Outcome of one power action.

    - `action`: "on" | "off".
    - `method`: controller that ran ("adb", "wol+adb", "websocket", ...).
    - `executed`: False when the device was already in the requested
      state (idempotent actions report success without executing).
    - `success`/`detail`: outcome of the attempt; success=False is a
      normal business answer, not a server error.
    """

    action: str
    method: str
    executed: bool
    success: bool
    detail: str = ""


class DevicePowerController(ABC):
    """How one device type answers power on/off."""

    #: Human-readable method name reported in PowerResult.method.
    method: str = "abstract"
    #: True when delivery needs the device's live WebSocket channel (the
    #: endpoint answers 409 while that channel is down).
    requires_live_channel: bool = False

    @abstractmethod
    async def turn_on(self, device: Device) -> PowerResult: ...

    @abstractmethod
    async def turn_off(self, device: Device) -> PowerResult: ...


def require_private_ip(device: Device) -> str:
    """Return the device's last reported IP, refusing non-private targets.

    The server shells out to that IP (adb / WOL) and the IP is only
    client-reported data: never aim outside the LAN.
    """
    ip = device.ip_address
    if not ip:
        raise PowerTargetError(f"device {device.device_uid} has no reported IP")
    try:
        parsed = ipaddress.ip_address(ip)
    except ValueError as exc:
        raise PowerTargetError(
            f"device {device.device_uid} reported an invalid IP: {ip!r}"
        ) from exc
    if not parsed.is_private:
        raise PowerTargetError(f"refusing non-private target IP {ip}")
    return ip


class PowerControllerRegistry:
    """device.type -> controller factory, with a fallback controller."""

    def __init__(self) -> None:
        self._factories: dict[str, Callable[[], DevicePowerController]] = {}
        self._fallback: Callable[[], DevicePowerController] | None = None

    def register(
        self, device_type: str, factory: Callable[[], DevicePowerController]
    ) -> None:
        self._factories[device_type] = factory

    def set_fallback(self, factory: Callable[[], DevicePowerController]) -> None:
        self._fallback = factory

    def for_device(self, device: Device) -> DevicePowerController:
        # Type matching is case/space tolerant ("Google TV" == "google_tv").
        key = (device.type or "").strip().lower()
        factory = self._factories.get(key) or self._fallback
        if factory is None:
            raise PowerTargetError(
                f"no power controller registered for device type {device.type!r}"
            )
        return factory()
