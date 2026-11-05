"""TEMPORAL: encendido y apagado global de la sala Cauce.

Implementacion de transicion pensada para durar hasta que exista el
control maestro individualizado por dispositivo. La documentacion
completa, incluida la guia de reemplazo, esta en
`backend/docs/room_power_temporal.md`.

Como funciona hoy:

- El backend corre con uvicorn directamente en el servidor Windows
  (sin Docker), por lo que puede invocar PowerShell con
  `subprocess.run` en un hilo. No se usa
  `asyncio.create_subprocess_exec` porque uvicorn instala
  `WindowsSelectorEventLoop` en Windows, que no soporta subprocesos
  asyncio (`NotImplementedError`).
- Encender/apagar dispara las tareas programadas existentes
  `Cauce_ON` / `Cauce_OFF` via `Start-ScheduledTask` (fire-and-forget:
  la API no espera a que la sala termine de encender/apagar).
- El estado se consulta con `Get-ScheduledTask` (State: si la tarea
  corre ahora) y `Get-ScheduledTaskInfo` (LastTaskResult y
  LastRunTime); Task Scheduler es la fuente de verdad del historial,
  no se persiste nada en la BD.

Puntos de extension para el reemplazo:

- `set_power()` es la unica entrada de escritura.
- `get_status()` es la unica entrada de lectura.
- `_run_powershell()` es el unico punto de contacto con el host: en
  Docker debera cambiarse por una llamada HTTP al bridge del host.
"""

import asyncio
import logging
import subprocess
from datetime import datetime

from app.core.config import get_settings
from app.core.exceptions import HostCommandError
from app.schemas.room import (
    PowerAction,
    RoomPowerStatus,
    RoomTaskStatus,
)

logger = logging.getLogger(__name__)

# PowerShell deberia resolver Start-ScheduledTask en milisegundos: el
# timeout solo protege contra un powershell.exe colgado.
POWERSHELL_TIMEOUT_SECONDS = 10

# Codigos de LastTaskResult que no representan una ejecucion finalizada.
# Nota: 267009 (0x41301, "en ejecucion") NO se usa para detectar la
# tarea en curso: LastTaskResult puede quedarse en 267009 un tiempo
# tras completar la tarea. El estado actual se consulta con el State
# de Get-ScheduledTask.
_TASK_RESULT_NEVER_RUN = 267011  # 0x41303: la tarea nunca ha corrido.

# Salida en tres lineas para no depender del formato de fecha de
# ConvertTo-Json en distintas versiones de PowerShell.
_STATUS_COMMAND_TEMPLATE = (
    "$task = Get-ScheduledTask -TaskName '{task_name}'; "
    "$info = $task | Get-ScheduledTaskInfo; "
    "Write-Output $task.State; "
    "Write-Output $info.LastTaskResult; "
    "Write-Output $info.LastRunTime.ToString('yyyy-MM-ddTHH:mm:ss')"
)

_START_COMMAND_TEMPLATE = "Start-ScheduledTask -TaskName '{task_name}'"


class RoomPowerService:
    """Logica de negocio del encendido/apagado temporal de la sala."""

    async def set_power(self, action: PowerAction) -> str:
        """Disparar la tarea programada correspondiente y devolver su nombre."""
        settings = get_settings()
        task_name = (
            settings.CAUCE_ROOM_ON_TASK
            if action == "on"
            else settings.CAUCE_ROOM_OFF_TASK
        )
        await self._run_powershell(_START_COMMAND_TEMPLATE.format(task_name=task_name))
        logger.info("Room power action '%s' triggered (task '%s')", action, task_name)
        return task_name

    async def get_status(self) -> RoomPowerStatus:
        """Consultar la ultima ejecucion de las tareas ON y OFF."""
        settings = get_settings()
        return RoomPowerStatus(
            on=await self._task_status(settings.CAUCE_ROOM_ON_TASK),
            off=await self._task_status(settings.CAUCE_ROOM_OFF_TASK),
        )

    async def _task_status(self, task_name: str) -> RoomTaskStatus:
        output = await self._run_powershell(
            _STATUS_COMMAND_TEMPLATE.format(task_name=task_name)
        )
        lines = output.splitlines()
        if len(lines) < 3:
            raise HostCommandError(
                f"Unexpected Get-ScheduledTask output for task '{task_name}'"
            )
        try:
            result_code = int(lines[1].strip())
        except ValueError as exc:
            raise HostCommandError(
                f"Invalid LastTaskResult for task '{task_name}': {lines[1]!r}"
            ) from exc

        running = lines[0].strip() == "Running"
        ever_ran = result_code != _TASK_RESULT_NEVER_RUN
        # LastRunTime de una tarea nunca ejecutada es un valor centinela
        # (01/01/0001): se reporta como None en lugar de una fecha basura.
        last_run_time = None
        if ever_ran:
            try:
                last_run_time = datetime.fromisoformat(lines[2].strip())
            except ValueError as exc:
                raise HostCommandError(
                    f"Invalid LastRunTime for task '{task_name}': {lines[2]!r}"
                ) from exc
        return RoomTaskStatus(
            task_name=task_name,
            last_run_time=last_run_time,
            last_task_result=result_code,
            running=running,
            succeeded=(result_code == 0) if ever_ran else None,
        )

    async def _run_powershell(self, command: str) -> str:
        """Ejecutar un comando de PowerShell en el host y devolver su stdout.

        La invocacion se hace en un hilo: el event loop SelectorEventLoop
        de uvicorn en Windows no implementa subprocesos asyncio.
        """
        return await asyncio.to_thread(self._run_powershell_sync, command)

    def _run_powershell_sync(self, command: str) -> str:
        try:
            completed = subprocess.run(
                (
                    "powershell",
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    command,
                ),
                capture_output=True,
                timeout=POWERSHELL_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            # subprocess.run mata el proceso antes de propagar la excepcion.
            raise HostCommandError(
                f"PowerShell timed out after {POWERSHELL_TIMEOUT_SECONDS}s: {command!r}"
            ) from None
        except OSError as exc:
            raise HostCommandError(f"Cannot launch powershell: {exc}") from exc

        if completed.returncode != 0:
            detail = completed.stderr.decode(errors="replace").strip()
            raise HostCommandError(
                f"PowerShell exited with {completed.returncode}: {detail}"
            )
        return completed.stdout.decode(errors="replace").strip()
