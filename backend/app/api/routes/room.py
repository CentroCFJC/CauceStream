"""TEMPORAL: encendido y apagado global de la sala Cauce.

Endpoint de transicion que dispara las tareas programadas de Windows
`Cauce_ON` / `Cauce_OFF`. Toda la logica y la guia de reemplazo estan
documentadas en `backend/docs/room_power_temporal.md`.
"""

from fastapi import APIRouter, Depends, status

from app.api.deps import get_room_power_service, require_permission
from app.models.user import User
from app.schemas.room import (
    RoomPowerAccepted,
    RoomPowerRequest,
    RoomPowerStatus,
)
from app.services.room_power_service import RoomPowerService

router = APIRouter(prefix="/room", tags=["room"])


@router.post(
    "/power",
    response_model=RoomPowerAccepted,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Turn the whole room on or off (temporary)",
)
async def set_room_power(
    payload: RoomPowerRequest,
    actor: User = Depends(require_permission("devices.control")),
    service: RoomPowerService = Depends(get_room_power_service),
):
    """Disparar la tarea programada de encendido o apagado global.

    Devuelve 202: la tarea se lanza en segundo plano y la API no espera
    a que la sala termine de encender o apagar. Usa `GET /room/power`
    para verificar el resultado de la ultima ejecucion.
    """
    task_name = await service.set_power(payload.action)
    return RoomPowerAccepted(action=payload.action, task_name=task_name)


@router.get(
    "/power",
    response_model=RoomPowerStatus,
    summary="Room power tasks status (temporary)",
)
async def get_room_power(
    actor: User = Depends(require_permission("devices.control")),
    service: RoomPowerService = Depends(get_room_power_service),
):
    """Ultimo resultado de las tareas Cauce_ON y Cauce_OFF.

    La fuente de verdad es Task Scheduler (Get-ScheduledTaskInfo); no se
    persiste nada en la base de datos.
    """
    return await service.get_status()
