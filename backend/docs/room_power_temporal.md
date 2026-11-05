# Encendido/apagado global de la sala — implementación TEMPORAL

> Estado: **transitoria**. Este documento existe para que el paso al
> control maestro individualizado por dispositivo (o a la ejecución en
> Docker) sea un cambio limpio y no una excavación arqueológica.

## Qué es

Endpoint de transición que enciende o apaga **toda la sala** disparando
las tareas programadas de Windows `Cauce_ON` y `Cauce_OFF` (que a su vez
ejecutan `cauce_on.bat` / `cauce_off.bat` en `D:\Syncthing\CAUCE\Control`).

## Contrato de API

| Método | Ruta | Permiso | Respuesta |
|---|---|---|---|
| POST | `/api/room/power` | `devices.control` | 202 `{action, task_name}` |
| GET | `/api/room/power` | `devices.control` | 200 estado de ambas tareas |

- Body del POST: `{"action": "on"} | {"action": "off"}`.
- El 202 significa "tarea disparada", no "sala encendida". El
  encendido/apagado real es asíncrono; el resultado se verifica con el
  GET (última ejecución de cada tarea según Task Scheduler).
- Errores de host (PowerShell no disponible, timeout, tarea fallida al
  lanzar): 502 con `{"code": "host_command_failed", ..."}`.

## Cómo funciona (suposiciones vigentes)

1. El backend corre con **uvicorn nativo en el servidor Windows** (sin
   Docker). Por eso puede ejecutar `powershell.exe` directamente: con
   `subprocess.run` en un hilo (`asyncio.to_thread`), ya que el
   SelectorEventLoop que uvicorn usa en Windows no soporta
   `asyncio.create_subprocess_exec` (`NotImplementedError`).
2. Encendido/apagado = `Start-ScheduledTask -TaskName '<tarea>'`
   (fire-and-forget; la API no espera el fin de la tarea).
3. Estado = `Get-ScheduledTask` (State: si la tarea corre ahora) +
   `Get-ScheduledTaskInfo` (`LastTaskResult` + `LastRunTime` local del
   servidor). Task Scheduler es la fuente de verdad del historial;
   **no se persiste nada en la BD** a propósito (principio de
   evolución incremental). Nota: `running` NO se deriva de
   `LastTaskResult == 267009`, que puede quedarse en ese valor tras
   completar la tarea; se usa el State.
4. Tareas supuestas configuradas con "ejecutar tanto si el usuario ha
   iniciado sesión" y privilegios suficientes.

## Configuración (env vars, ver `app/core/config.py`)

| Variable | Default | Uso |
|---|---|---|
| `CAUCE_ROOM_ON_TASK` | `Cauce_ON` | Nombre de la tarea de encendido |
| `CAUCE_ROOM_OFF_TASK` | `Cauce_OFF` | Nombre de la tarea de apagado |

## Archivos involucrados

```
app/core/config.py                 CAUCE_ROOM_ON_TASK / CAUCE_ROOM_OFF_TASK
app/core/exceptions.py             HostCommandError (502)
app/schemas/room.py                RoomPowerRequest / RoomPowerAccepted / RoomPowerStatus
app/services/room_power_service.py TODA la lógica (ver docstring)
app/api/routes/room.py             solo HTTP
app/api/deps.py                    get_room_power_service (sin sesión de BD)
tests/api/test_room.py             tests del endpoint y del seam de PowerShell
```

## Cambio a Docker (primer cambio previsto)

`RoomPowerService._run_powershell()` es el **único** punto de contacto
con el host. En un contenedor Linux un `.bat`/`powershell.exe` no es
ejecutable: reemplazar ese método por una llamada HTTP (httpx) a un
bridge mínimo en el host Windows que ejecute `Start-ScheduledTask`.
Route, schemas, permiso y tests de API no cambian; solo el método y los
tests del seam.

## Reemplazo por el control maestro individualizado (cambio definitivo)

Checklist para destruir esto de forma limpia:

1. Migrar los clientes (frontend / app móvil) al control por
   dispositivo (`/api/devices/{uid}/power`, ya existente en
   `app/api/routes/devices.py` para dispositivos que soportan el
   protocolo).
2. Implementar la operación por dispositivo para los tipos restantes
   (los `.bat` actuales ya coordinan por tipo en
   `D:\Syncthing\CAUCE\Control\<Tipo>\`).
3. Decidir si la acción "toda la sala" sobrevive como un agrupador
   ("encender todos los dispositivos de la sala") sobre el control
   individual — probablemente sí, como endpoint de nivel sala con
   persistencia de estado real por dispositivo.
4. Eliminar: `app/api/routes/room.py`, `app/services/room_power_service.py`,
   `app/schemas/room.py`, `get_room_power_service` en `deps.py`, las dos
   settings, `HostCommandError` (si queda sin uso) y
   `tests/api/test_room.py`. Desregistrar `room` en
   `app/api/router.py`.
5. Conservar las tareas programadas `Cauce_ON`/`Cauce_OFF` solo si el
   nuevo control necesita un mecanismo de arranque del host; si no,
   deshabilitarlas.
