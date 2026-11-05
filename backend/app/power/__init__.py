"""Power controller registry (application singleton).

`build_power_registry` wires each canonical device `type` to its
controller; `get_power_registry` returns the shared instance (FastAPI
dependency in app.api.deps).
"""

from app.core.config import get_settings
from app.power.adb import AdbControllerConfig, AdbPowerController
from app.power.base import PowerControllerRegistry
from app.power.websocket import WebSocketPowerController

# Canonical device.type values handled by the ADB controller (Android TV
# boxes, ported from CAUCE/Control/GoogleTv), plus tolerant aliases for
# types registered before the canonical vocabulary existed.
ADB_DEVICE_TYPES = ("google_tv", "android_tv")
_ADB_TYPE_ALIASES = ("googletv", "google tv", "androidtv", "android tv", "android_tv_box")


def normalize_device_type(device_type: str) -> str:
    return (device_type or "").strip().lower()


def build_power_registry() -> PowerControllerRegistry:
    settings = get_settings()
    registry = PowerControllerRegistry()
    adb_types = {normalize_device_type(t) for t in (*ADB_DEVICE_TYPES, *_ADB_TYPE_ALIASES)}
    for device_type in adb_types:
        registry.register(
            device_type,
            lambda: AdbPowerController(AdbControllerConfig.from_settings(settings)),
        )
    # Types without a native controller keep the original in-app method.
    registry.set_fallback(WebSocketPowerController)
    return registry


_registry: PowerControllerRegistry | None = None


def get_power_registry() -> PowerControllerRegistry:
    global _registry
    if _registry is None:
        _registry = build_power_registry()
    return _registry
