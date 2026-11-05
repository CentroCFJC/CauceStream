"""Tests for the power controller registry and the target-IP guard."""

import pytest

from app.models.device import Device
from app.power import ADB_DEVICE_TYPES, build_power_registry
from app.power.adb import AdbPowerController
from app.power.base import PowerTargetError, require_private_ip
from app.power.websocket import WebSocketPowerController


def make_device(**kwargs) -> Device:
    defaults = dict(
        device_uid="CAUCE-001",
        name="Pantalla",
        type="google_tv",
        ip_address="10.15.1.151",
    )
    defaults.update(kwargs)
    return Device(**defaults)


def test_adb_device_types_resolve_to_adb_controller():
    registry = build_power_registry()
    for device_type in ADB_DEVICE_TYPES:
        controller = registry.for_device(make_device(type=device_type))
        assert isinstance(controller, AdbPowerController)


def test_type_matching_is_case_and_space_tolerant():
    registry = build_power_registry()
    for alias in ("Google TV", "ANDROID_TV", " android tv ", "googletv"):
        controller = registry.for_device(make_device(type=alias))
        assert isinstance(controller, AdbPowerController), alias


def test_unknown_type_falls_back_to_websocket():
    registry = build_power_registry()
    controller = registry.for_device(make_device(type="screen"))
    assert isinstance(controller, WebSocketPowerController)
    assert controller.requires_live_channel


def test_require_private_ip_accepts_lan_ip():
    assert require_private_ip(make_device(ip_address="10.15.1.151")) == "10.15.1.151"
    assert require_private_ip(make_device(ip_address="192.168.1.20")) == "192.168.1.20"


def test_require_private_ip_rejects_missing_or_public():
    with pytest.raises(PowerTargetError):
        require_private_ip(make_device(ip_address=None))
    with pytest.raises(PowerTargetError):
        require_private_ip(make_device(ip_address="8.8.8.8"))
    with pytest.raises(PowerTargetError):
        require_private_ip(make_device(ip_address="not-an-ip"))
