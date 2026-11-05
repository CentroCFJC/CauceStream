# Encendido/apagado individual por dispositivo (server-side)

`POST /api/devices/{device_uid}/power` ejecuta la acción **desde el
servidor**, con el controlador registrado para el `type` del dispositivo,
usando la IP que el dispositivo reportó en su último heartbeat
(`devices.ip_address`). Ya no depende de los permisos de la app cliente
(Android no permite apagar la pantalla desde una app sin Device Owner).

## Arquitectura

```
app/power/
├── base.py        # PowerResult, DevicePowerController (ABC), registry, guard de IP privada
├── wol.py         # magic packet Wake-on-LAN (compartido)
├── adb.py         # AdbPowerController: google_tv / android_tv (portado de CAUCE/Control/GoogleTv)
└── websocket.py   # WebSocketPowerController: fallback (método in-app original, power.command)
```

- El **registry** (`get_power_registry()`, singleton) mapea `device.type`
  canónico → controller. Tipos sin controller nativo caen al fallback
  WebSocket (409 si no hay canal vivo).
- Cada controller implementa `turn_on(device)` / `turn_off(device)` y
  devuelve un `PowerResult` (`method`, `executed`, `success`, `detail`).
  `executed=False` + `success=True` = ya estaba en ese estado
  (idempotente).
- Todo el trabajo bloqueante (subprocess adb, ping, sleeps, sockets) va
  en `asyncio.to_thread`: el event loop de Windows no soporta subprocesos
  asyncio (igual que `room_power_service`).
- El endpoint envuelve la ejecución en `asyncio.wait_for` con
  `CAUCE_POWER_TOTAL_TIMEOUT_S` (504 si se agota).

## ADB (google_tv / android_tv)

Portado de `CAUCE/Control/GoogleTv/google_tv_sala.py`:

- **off**: `adb connect <ip>:5555`; si no conecta y no hay ping → ya
  apagado (éxito, no ejecutado); si hay ping pero no ADB → fallo.
  Si conecta: `dumpsys power` → `mWakefulness=Asleep` = ya en standby;
  si no, `input keyevent 223` (SLEEP), fallback `26` (POWER).
- **on**: si ADB responde → `input keyevent 224` (WAKEUP), fallback 26.
  Si no → Wake-on-LAN a `devices.mac_address` (broadcast + unicast),
  esperar ping (`CAUCE_POWER_ON_BOOT_WAIT_S`), reintentar ADB, keyevent
  224/26. Sin MAC registrada no se puede hacer WOL.

Requisitos del box: `adb tcpip 5555` habilitado (adb over network).

## Datos y configuración

- `devices.mac_address` (migración 0009): la reporta el cliente en el
  heartbeat (`mac_address`, campo general) o se registra a mano.
- Settings (env): `CAUCE_ADB_PATH`, `CAUCE_ADB_PORT`,
  `CAUCE_ADB_CONNECT_TIMEOUT_S`, `CAUCE_ADB_SHELL_TIMEOUT_S`,
  `CAUCE_PING_TIMEOUT_S`, `CAUCE_POWER_ON_BOOT_WAIT_S`,
  `CAUCE_POWER_ON_PING_INTERVAL_S`, `CAUCE_POWER_TOTAL_TIMEOUT_S`,
  `CAUCE_WOL_PORTS`.

## Seguridad

- El objetivo (IP reportada por el propio dispositivo) se valida como
  **privada** antes de ejecutar nada (`require_private_ip`).
- Timeouts en cada subproceso y un deadline global por comando.
- El estado autoritativo de la pantalla sigue viniendo del heartbeat
  (`device_state`); la respuesta del endpoint describe solo el intento.

## Tipos canónicos

`google_tv` / `android_tv` → ADB (el matching es tolerante a
mayúsculas/espacios: "Google TV" también matchea). Fallback WebSocket
para cualquier otro `type`. Próximos: `windows_pc` (WOL + shutdown
remoto), `samsung_tv` (protocolo MDC, ver `CAUCE/Control/Samsung`).

**Dispositivos ya registrados con un type viejo** ("TV", "PC", ...)
siguen cayendo al fallback WebSocket (y el cliente responde
`standby_denied` si no está como Device Owner). Para migrarlos sin
borrarlos: `PATCH /api/devices/{device_uid}` con `{"type": "google_tv"}`
(o desde el frontend: botón de editar en la tarjeta INFORMACION del
detalle). La UI de registro envía siempre el type canónico.
