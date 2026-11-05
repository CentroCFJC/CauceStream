"""Unit tests for AdbPowerController: adb/ping/wol/sleep are all faked,
so no device or adb binary is needed."""

import subprocess

from app.models.device import Device
from app.power.adb import AdbControllerConfig, AdbPowerController, parse_wakefulness

IP = "10.15.1.153"
MAC = "7C:01:3E:7A:7D:52"


def make_device(**kwargs) -> Device:
    defaults = dict(
        device_uid="CAUCE-VR2",
        name="TV VR2",
        type="google_tv",
        ip_address=IP,
        mac_address=MAC,
    )
    defaults.update(kwargs)
    return Device(**defaults)


def completed(args, returncode=0, stdout="", stderr=""):
    return subprocess.CompletedProcess(args, returncode, stdout, stderr)


class FakeAdb:
    """adb_runner fake.

    - `connect_ok` / `fail_connects`: control `adb connect` (the first
      `fail_connects` connect attempts fail, then it succeeds).
    - `shell`: map "shell command" -> (returncode, stdout).
    - `fail_keyevents`: keyevent codes that fail.
    """

    def __init__(self, connect_ok=True, fail_connects=0, shell=None, fail_keyevents=()):
        self.connect_ok = connect_ok
        self.fail_connects = fail_connects
        self.shell = shell or {}
        self.fail_keyevents = set(fail_keyevents)
        self.calls: list[str] = []
        self._connects = 0

    def __call__(self, args, timeout):
        self.calls.append(" ".join(args))
        if args[0] == "connect":
            self._connects += 1
            if self.connect_ok and self._connects > self.fail_connects:
                return completed(args, 0, f"connected to {args[1]}")
            return completed(args, 1, "", "Connection refused")
        if args[0] == "-s" and len(args) >= 4 and args[2] == "shell":
            cmd = " ".join(args[3:])
            self.calls.append(cmd)
            if cmd.startswith("input keyevent"):
                code = cmd.rsplit(" ", 1)[1]
                if code in self.fail_keyevents:
                    return completed(args, 1, "", "error")
                return completed(args, 0, "", "")
            return completed(args, *self.shell.get(cmd, (0, "")))
        return completed(args, 0, "", "")


def make_controller(adb, ping_ok=True, wol_log=None):
    cfg = AdbControllerConfig(
        quick_attempts=1,
        connect_attempts=3,
        retry_interval=0,
        quick_retry_interval=0,
        ping_interval=0.01,
        boot_wait=0.05,
        adb_daemon_ready_wait=0,
    )
    log = wol_log if wol_log is not None else []
    return AdbPowerController(
        cfg,
        adb_runner=adb,
        pinger=lambda ip, timeout: ping_ok,
        sleeper=lambda seconds: None,
        wol_sender=lambda mac, ip, ports: log.append((mac, ip, tuple(ports))),
    )


# --- parse_wakefulness ---


def test_parse_wakefulness():
    assert parse_wakefulness("  mWakefulness=Awake\n") == "Awake"
    assert parse_wakefulness("mWakefulness=Asleep") == "Asleep"
    assert parse_wakefulness("sin el campo") is None


# --- turn_off ---


async def test_turn_off_no_ip_reported_fails():
    controller = make_controller(FakeAdb(), ping_ok=False)
    result = await controller.turn_off(make_device(ip_address=None))
    assert not result.success
    assert result.method == "adb"
    assert "no reported IP" in result.detail


async def test_turn_off_public_ip_rejected():
    controller = make_controller(FakeAdb(), ping_ok=False)
    result = await controller.turn_off(make_device(ip_address="8.8.8.8"))
    assert not result.success
    assert "non-private" in result.detail


async def test_turn_off_already_off_when_no_ping_and_no_adb():
    adb = FakeAdb(connect_ok=False)
    controller = make_controller(adb, ping_ok=False)
    result = await controller.turn_off(make_device())
    assert result.success
    assert not result.executed  # idempotente: ya estaba apagado
    assert "ya apagado" in result.detail


async def test_turn_off_ping_but_no_adb_fails():
    controller = make_controller(FakeAdb(connect_ok=False), ping_ok=True)
    result = await controller.turn_off(make_device())
    assert not result.success
    assert "ping" in result.detail


async def test_turn_off_already_asleep_is_success_without_keyevent():
    adb = FakeAdb(shell={"dumpsys power": (0, "mWakefulness=Asleep\nDisplay Power: OFF")})
    controller = make_controller(adb, ping_ok=True)
    result = await controller.turn_off(make_device())
    assert result.success
    assert not result.executed
    assert "standby" in result.detail
    assert not any("input keyevent" in c for c in adb.calls)


async def test_turn_off_sends_sleep_keyevent_when_awake():
    adb = FakeAdb(shell={"dumpsys power": (0, "mWakefulness=Awake\n")})
    controller = make_controller(adb, ping_ok=True)
    result = await controller.turn_off(make_device())
    assert result.success
    assert result.executed
    assert "SLEEP (223)" in result.detail
    assert any("input keyevent 223" in c for c in adb.calls)


async def test_turn_off_falls_back_to_power_keyevent():
    adb = FakeAdb(
        shell={"dumpsys power": (0, "mWakefulness=Awake\n")},
        fail_keyevents={"223"},
    )
    controller = make_controller(adb, ping_ok=True)
    result = await controller.turn_off(make_device())
    assert result.success
    assert "POWER (26)" in result.detail


async def test_turn_off_fails_when_no_keyevent_works():
    adb = FakeAdb(
        shell={"dumpsys power": (0, "mWakefulness=Awake\n")},
        fail_keyevents={"223", "26"},
    )
    controller = make_controller(adb, ping_ok=True)
    result = await controller.turn_off(make_device())
    assert not result.success


# --- turn_on ---


async def test_turn_on_direct_wakeup_when_adb_answers():
    adb = FakeAdb(connect_ok=True)
    controller = make_controller(adb, ping_ok=True)
    result = await controller.turn_on(make_device())
    assert result.success
    assert result.executed
    assert result.method == "adb"
    assert any("input keyevent 224" in c for c in adb.calls)


async def test_turn_on_falls_back_to_power_keyevent():
    adb = FakeAdb(connect_ok=True, fail_keyevents={"224"})
    controller = make_controller(adb, ping_ok=True)
    result = await controller.turn_on(make_device())
    assert result.success
    assert "POWER (26)" in result.detail


async def test_turn_on_cold_boot_uses_wol_then_adb():
    adb = FakeAdb(connect_ok=True, fail_connects=1)  # quick attempt fails, later connect ok
    wol_log: list = []
    controller = make_controller(adb, ping_ok=True, wol_log=wol_log)
    result = await controller.turn_on(make_device())
    assert result.success
    assert result.method == "wol+adb"
    assert wol_log == [(MAC, IP, (9, 7))]
    assert any("input keyevent 224" in c for c in adb.calls)


async def test_turn_on_wol_without_ping_fails():
    adb = FakeAdb(connect_ok=False)
    wol_log: list = []
    controller = make_controller(adb, ping_ok=False, wol_log=wol_log)
    result = await controller.turn_on(make_device())
    assert not result.success
    assert result.method == "wol+adb"
    assert wol_log  # WOL sí se envió
    assert "ping" in result.detail


async def test_turn_on_without_mac_and_no_adb_fails():
    adb = FakeAdb(connect_ok=False)
    wol_log: list = []
    controller = make_controller(adb, ping_ok=True, wol_log=wol_log)
    result = await controller.turn_on(make_device(mac_address=None))
    assert not result.success
    assert "MAC" in result.detail
    assert not wol_log  # sin MAC no se envía WOL
