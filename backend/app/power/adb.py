"""ADB power controller for Android TV boxes (Google TV / Android TV).

Ported from CAUCE/Control/GoogleTv/google_tv_sala.py:

- off: `adb connect <ip>:<port>`; if unreachable and no ping, the device
  is already off (success, not executed); if ping but no ADB, failure.
  When connected, check `dumpsys power` mWakefulness: Asleep means
  already in standby. Otherwise send `input keyevent 223` (SLEEP),
  fallback `26` (POWER).
- on: if ADB already answers, send `input keyevent 224` (WAKEUP),
  fallback `26` (POWER). If not, send Wake-on-LAN to the device MAC,
  wait for ping, reconnect ADB with retries, then keyevent 224/26.

All blocking work (subprocess, ping, sleeps, sockets) runs in threads:
uvicorn on Windows uses WindowsSelectorEventLoop, which has no asyncio
subprocess support (same constraint as room_power_service).
"""

from __future__ import annotations

import asyncio
import re
import subprocess
from collections.abc import Callable
from dataclasses import dataclass

from app.core.config import Settings, get_settings
from app.models.device import Device
from app.power.base import (
    DevicePowerController,
    PowerResult,
    PowerTargetError,
    require_private_ip,
)
from app.power.wol import send_wake_on_lan

KEYCODE_SLEEP = "223"
KEYCODE_WAKEUP = "224"
KEYCODE_POWER = "26"

# Injectable seams for tests: every blocking primitive can be faked.
AdbRunner = Callable[[list[str], float], "subprocess.CompletedProcess[str]"]
Pinger = Callable[[str, float], bool]
Sleeper = Callable[[float], None]
WolSender = Callable[[str, str, tuple[int, ...]], None]


@dataclass(frozen=True)
class AdbControllerConfig:
    adb_path: str = "adb"
    port: int = 5555
    connect_timeout: float = 10.0
    shell_timeout: float = 10.0
    ping_timeout: float = 5.0
    boot_wait: float = 60.0
    ping_interval: float = 3.0
    connect_attempts: int = 10
    retry_interval: float = 3.0
    quick_attempts: int = 2
    quick_retry_interval: float = 1.0
    adb_daemon_ready_wait: float = 5.0
    wol_ports: tuple[int, ...] = (9, 7)

    @classmethod
    def from_settings(cls, settings: Settings) -> "AdbControllerConfig":
        return cls(
            adb_path=settings.CAUCE_ADB_PATH,
            port=settings.CAUCE_ADB_PORT,
            connect_timeout=settings.CAUCE_ADB_CONNECT_TIMEOUT_S,
            shell_timeout=settings.CAUCE_ADB_SHELL_TIMEOUT_S,
            ping_timeout=settings.CAUCE_PING_TIMEOUT_S,
            boot_wait=settings.CAUCE_POWER_ON_BOOT_WAIT_S,
            ping_interval=settings.CAUCE_POWER_ON_PING_INTERVAL_S,
            wol_ports=tuple(settings.wol_ports),
        )


def default_adb_runner(adb_path: str) -> AdbRunner:
    def run(args: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [adb_path, *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )

    return run


def default_pinger(ip: str, timeout: float) -> bool:
    """Windows ping: -n 1 -w <ms>."""
    try:
        result = subprocess.run(
            ["ping", "-n", "1", "-w", str(int(timeout * 1000)), ip],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout + 2,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _noop_sleep(_seconds: float) -> None:
    return None


_WAKEFULNESS_RE = re.compile(r"mWakefulness=(\w+)")


def parse_wakefulness(dumpsys_output: str) -> str | None:
    match = _WAKEFULNESS_RE.search(dumpsys_output)
    return match.group(1) if match else None


class AdbPowerController(DevicePowerController):
    """Power on/off of an Android TV box over ADB (from CAUCE/Control)."""

    method = "adb"

    def __init__(
        self,
        config: AdbControllerConfig | None = None,
        *,
        adb_runner: AdbRunner | None = None,
        pinger: Pinger | None = None,
        sleeper: Sleeper | None = None,
        wol_sender: WolSender | None = None,
    ) -> None:
        self.config = config or AdbControllerConfig()
        self._adb_runner = adb_runner or default_adb_runner(self.config.adb_path)
        self._pinger = pinger or default_pinger
        self._sleeper = sleeper or _noop_sleep
        self._wol_sender = wol_sender or send_wake_on_lan

    # --- blocking primitives, always via asyncio.to_thread ---

    def _target(self, ip: str) -> str:
        return f"{ip}:{self.config.port}"

    async def _adb_connect(self, ip: str, *, attempts: int, retry_interval: float) -> bool:
        cfg = self.config
        target = self._target(ip)
        for attempt in range(1, attempts + 1):
            try:
                await asyncio.to_thread(self._run_adb, ["disconnect", target], 5.0)
                result = await asyncio.to_thread(
                    self._run_adb, ["connect", target], cfg.connect_timeout
                )
            except (OSError, subprocess.SubprocessError):
                result = None
            if result is not None and "connected to" in (result.stdout or "").lower():
                return True
            if attempt < attempts:
                await asyncio.to_thread(self._sleeper, retry_interval)
        return False

    def _run_adb(self, args: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
        return self._adb_runner(args, timeout)

    async def _adb_shell(
        self, ip: str, *args: str
    ) -> subprocess.CompletedProcess[str] | None:
        try:
            return await asyncio.to_thread(
                self._run_adb,
                ["-s", self._target(ip), "shell", *args],
                self.config.shell_timeout,
            )
        except (OSError, subprocess.SubprocessError):
            return None

    async def _ping(self, ip: str) -> bool:
        return await asyncio.to_thread(self._pinger, ip, self.config.ping_timeout)

    async def _wait_for_ping(self, ip: str) -> bool:
        cfg = self.config
        waited = 0.0
        while waited < cfg.boot_wait:
            if await self._ping(ip):
                return True
            await asyncio.to_thread(self._sleeper, cfg.ping_interval)
            waited += cfg.ping_interval
        return False

    async def _wakefulness(self, ip: str) -> str | None:
        result = await self._adb_shell(ip, "dumpsys", "power")
        if result is None or result.returncode != 0:
            return None
        return parse_wakefulness(result.stdout or "")

    async def _keyevent(self, ip: str, code: str) -> bool:
        result = await self._adb_shell(ip, "input", "keyevent", code)
        return result is not None and result.returncode == 0

    # --- public actions ---

    async def turn_off(self, device: Device) -> PowerResult:
        try:
            ip = require_private_ip(device)
        except PowerTargetError as exc:
            return PowerResult("off", self.method, False, False, str(exc))

        cfg = self.config
        connected = await self._adb_connect(
            ip, attempts=cfg.quick_attempts, retry_interval=cfg.quick_retry_interval
        )
        if not connected:
            if not await self._ping(ip):
                return PowerResult(
                    "off", self.method, False, True,
                    "ya apagado (sin respuesta a ping ni ADB)",
                )
            return PowerResult(
                "off", self.method, False, False,
                "responde a ping pero no acepta conexión ADB",
            )

        try:
            wakefulness = await self._wakefulness(ip)
            if wakefulness == "Asleep":
                return PowerResult(
                    "off", self.method, False, True,
                    "ya estaba en standby (mWakefulness=Asleep)",
                )
            if await self._keyevent(ip, KEYCODE_SLEEP):
                return PowerResult(
                    "off", self.method, True, True, "keyevent SLEEP (223) enviado"
                )
            if await self._keyevent(ip, KEYCODE_POWER):
                return PowerResult(
                    "off", self.method, True, True,
                    "keyevent POWER (26) enviado (fallback)",
                )
            return PowerResult(
                "off", self.method, False, False,
                "ADB conectado pero no se pudo enviar el keyevent",
            )
        finally:
            await asyncio.to_thread(self._run_adb, ["disconnect", self._target(ip)], 5.0)

    async def turn_on(self, device: Device) -> PowerResult:
        try:
            ip = require_private_ip(device)
        except PowerTargetError as exc:
            return PowerResult("on", self.method, False, False, str(exc))

        cfg = self.config

        # Fast path: the box is already up and answering ADB.
        if await self._adb_connect(
            ip, attempts=cfg.quick_attempts, retry_interval=cfg.quick_retry_interval
        ):
            if await self._keyevent(ip, KEYCODE_WAKEUP):
                return PowerResult(
                    "on", self.method, True, True, "keyevent WAKEUP (224) enviado"
                )
            if await self._keyevent(ip, KEYCODE_POWER):
                return PowerResult(
                    "on", self.method, True, True,
                    "keyevent POWER (26) enviado (fallback)",
                )
            return PowerResult(
                "on", self.method, False, False,
                "ADB conectado pero no se pudo enviar el keyevent",
            )

        # Cold boot: Wake-on-LAN, then wait for the OS and the adb daemon.
        mac = device.mac_address
        if not mac:
            return PowerResult(
                "on", self.method, False, False,
                "sin MAC registrada: no se puede hacer Wake-on-LAN",
            )
        method = "wol+adb"
        await asyncio.to_thread(self._wol_sender, mac, ip, cfg.wol_ports)
        if not await self._wait_for_ping(ip):
            return PowerResult(
                "on", method, False, False,
                f"WOL enviado a {mac} pero el dispositivo no respondió a ping "
                f"en {cfg.boot_wait}s",
            )
        await asyncio.to_thread(self._sleeper, cfg.adb_daemon_ready_wait)
        if not await self._adb_connect(
            ip, attempts=cfg.connect_attempts, retry_interval=cfg.retry_interval
        ):
            return PowerResult(
                "on", method, False, False,
                "respondió a ping tras WOL pero ADB no conectó",
            )
        if await self._keyevent(ip, KEYCODE_WAKEUP):
            return PowerResult("on", method, True, True, "WOL + keyevent WAKEUP (224)")
        if await self._keyevent(ip, KEYCODE_POWER):
            return PowerResult(
                "on", method, True, True, "WOL + keyevent POWER (26) (fallback)"
            )
        return PowerResult(
            "on", method, False, False,
            "ADB conectado tras WOL pero no se pudo enviar el keyevent",
        )
