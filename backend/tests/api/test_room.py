"""Tests for the temporary room power endpoint (POST/GET /api/room/power)
and its service seam (_run_powershell).

The real PowerShell invocation is never exercised here: the service
seam is monkeypatched. Tests run the app in-process like the other API
tests.
"""

import pytest

from app.api.deps import get_room_power_service
from app.core.exceptions import HostCommandError
from app.main import app
from app.schemas.room import RoomPowerStatus, RoomTaskStatus
from app.services.room_power_service import RoomPowerService
from tests.conftest import (
    ADMIN_EMAIL,
    ADMIN_PASSWORD,
    MEDIATOR_EMAIL,
    MEDIATOR_PASSWORD,
    bearer,
    login,
)


class FakeRoomPowerService:
    """In-memory replacement for RoomPowerService (API-level tests)."""

    def __init__(self) -> None:
        self.actions: list[str] = []
        self.fail = False
        self.status = RoomPowerStatus(
            on=RoomTaskStatus(
                task_name="Cauce_ON",
                last_run_time=None,
                last_task_result=267011,
                running=False,
                succeeded=None,
            ),
            off=RoomTaskStatus(
                task_name="Cauce_OFF",
                last_run_time=None,
                last_task_result=267011,
                running=False,
                succeeded=None,
            ),
        )

    async def set_power(self, action: str) -> str:
        if self.fail:
            raise HostCommandError("Powershell.exe not found")
        self.actions.append(action)
        return "Cauce_ON" if action == "on" else "Cauce_OFF"

    async def get_status(self) -> RoomPowerStatus:
        if self.fail:
            raise HostCommandError("Get-ScheduledTaskInfo failed")
        return self.status


@pytest.fixture
def room_service():
    return FakeRoomPowerService()


@pytest.fixture
def use_fake_room_service(room_service):
    app.dependency_overrides[get_room_power_service] = lambda: room_service
    yield room_service
    app.dependency_overrides.pop(get_room_power_service, None)


async def test_power_requires_authentication(client):
    response = await client.post("/api/room/power", json={"action": "on"})

    assert response.status_code == 401


async def test_power_forbidden_for_mediator(client, mediator, use_fake_room_service):
    token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)

    response = await client.post(
        "/api/room/power", json={"action": "on"}, headers=bearer(token)
    )

    assert response.status_code == 403
    assert use_fake_room_service.actions == []


async def test_power_rejects_invalid_action(client, admin):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await client.post(
        "/api/room/power", json={"action": "restart"}, headers=bearer(token)
    )

    assert response.status_code == 422


async def test_power_on_returns_accepted(client, admin, use_fake_room_service):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await client.post(
        "/api/room/power", json={"action": "on"}, headers=bearer(token)
    )

    assert response.status_code == 202
    assert response.json() == {"action": "on", "task_name": "Cauce_ON"}
    assert use_fake_room_service.actions == ["on"]


async def test_power_off_returns_accepted(client, admin, use_fake_room_service):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await client.post(
        "/api/room/power", json={"action": "off"}, headers=bearer(token)
    )

    assert response.status_code == 202
    assert response.json() == {"action": "off", "task_name": "Cauce_OFF"}


async def test_power_failure_returns_502(client, admin, use_fake_room_service):
    use_fake_room_service.fail = True
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await client.post(
        "/api/room/power", json={"action": "on"}, headers=bearer(token)
    )

    assert response.status_code == 502
    assert response.json()["code"] == "host_command_failed"


async def test_status_requires_permission(client, mediator, use_fake_room_service):
    token = await login(client, MEDIATOR_EMAIL, MEDIATOR_PASSWORD)

    response = await client.get("/api/room/power", headers=bearer(token))

    assert response.status_code == 403


async def test_status_returns_task_state(client, admin, use_fake_room_service):
    token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)

    response = await client.get("/api/room/power", headers=bearer(token))

    assert response.status_code == 200
    body = response.json()
    assert body["on"]["task_name"] == "Cauce_ON"
    assert body["on"]["last_task_result"] == 267011
    assert body["on"]["last_run_time"] is None
    assert body["on"]["succeeded"] is None
    assert body["off"]["task_name"] == "Cauce_OFF"


# --- Service seam tests (_run_powershell monkeypatched) ---


class RecordingPowershell:
    """Replaces RoomPowerService._run_powershell: records commands."""

    def __init__(self, output: str = "") -> None:
        self.commands: list[str] = []
        self.output = output

    async def __call__(self, service_self, command: str) -> str:
        self.commands.append(command)
        return self.output


async def test_set_power_triggers_on_task(monkeypatch):
    recorder = RecordingPowershell()
    monkeypatch.setattr(RoomPowerService, "_run_powershell", recorder)

    task_name = await RoomPowerService().set_power("on")

    assert task_name == "Cauce_ON"
    assert recorder.commands == ["Start-ScheduledTask -TaskName 'Cauce_ON'"]


async def test_set_power_triggers_off_task(monkeypatch):
    recorder = RecordingPowershell()
    monkeypatch.setattr(RoomPowerService, "_run_powershell", recorder)

    task_name = await RoomPowerService().set_power("off")

    assert task_name == "Cauce_OFF"
    assert recorder.commands == ["Start-ScheduledTask -TaskName 'Cauce_OFF'"]


async def test_get_status_parses_last_run(monkeypatch):
    recorder = RecordingPowershell(output="Ready\n0\n2026-10-26T10:47:00")
    monkeypatch.setattr(RoomPowerService, "_run_powershell", recorder)

    status = await RoomPowerService().get_status()

    assert status.on.task_name == "Cauce_ON"
    assert status.on.last_task_result == 0
    assert status.on.succeeded is True
    assert status.on.running is False
    assert status.on.last_run_time is not None
    assert status.on.last_run_time.year == 2026
    assert status.off.last_run_time.year == 2026


async def test_get_status_handles_never_run(monkeypatch):
    # 267011 (0x41303): the task has never run.
    recorder = RecordingPowershell(output="Ready\n267011\n0001-01-01T00:00:00")
    monkeypatch.setattr(RoomPowerService, "_run_powershell", recorder)

    status = await RoomPowerService().get_status()

    assert status.on.last_task_result == 267011
    assert status.on.last_run_time is None
    assert status.on.succeeded is None
    assert status.on.running is False


async def test_get_status_detects_running(monkeypatch):
    # State 'Running' is the source of truth for "running now".
    recorder = RecordingPowershell(output="Running\n267009\n2026-10-26T11:04:00")
    monkeypatch.setattr(RoomPowerService, "_run_powershell", recorder)

    status = await RoomPowerService().get_status()

    assert status.on.running is True
    assert status.on.succeeded is False


async def test_get_status_not_running_despite_stale_result(monkeypatch):
    # LastTaskResult can stay at 267009 (0x41301) briefly after the
    # task finished: only the State decides "running".
    recorder = RecordingPowershell(output="Ready\n267009\n2026-10-26T11:05:00")
    monkeypatch.setattr(RoomPowerService, "_run_powershell", recorder)

    status = await RoomPowerService().get_status()

    assert status.on.running is False
    assert status.on.succeeded is False


async def test_get_status_rejects_unexpected_output(monkeypatch):
    recorder = RecordingPowershell(output="")
    monkeypatch.setattr(RoomPowerService, "_run_powershell", recorder)

    with pytest.raises(HostCommandError):
        await RoomPowerService().get_status()
