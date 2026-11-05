"""Esquemas del endpoint temporal de encendido/apagado global de la sala.

Ver `backend/docs/room_power_temporal.md`: esta implementacion es
TEMPORAL y sera reemplazada por el control maestro individualizado
por dispositivo.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel

PowerAction = Literal["on", "off"]


class RoomPowerRequest(BaseModel):
    """Orden de encendido o apagado global de la sala."""

    action: PowerAction


class RoomPowerAccepted(BaseModel):
    """Confirmacion de que la orden fue disparada.

    El encendido/apagado real es asincronico (tarea programada de
    Windows); este endpoint solo confirma el disparo.
    """

    action: PowerAction
    task_name: str


class RoomTaskStatus(BaseModel):
    """Estado de una tarea programada (Cauce_ON o Cauce_OFF)."""

    task_name: str
    # Hora local del servidor en que la tarea corrio por ultima vez.
    last_run_time: datetime | None
    # Codigo de resultado de la ultima ejecucion (0 = exito).
    last_task_result: int | None
    running: bool
    # None si la tarea nunca ha corrido.
    succeeded: bool | None


class RoomPowerStatus(BaseModel):
    """Estado combinado de las tareas de encendido y apagado."""

    on: RoomTaskStatus
    off: RoomTaskStatus
