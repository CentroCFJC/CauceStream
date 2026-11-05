# Cauce Backend

Backend REST del sistema **Cauce**, construido con FastAPI. Esta etapa contiene Ãºnicamente la infraestructura base (esqueleto): configuraciÃ³n, base de datos, router principal, health check, logging, CORS, manejo bÃ¡sico de errores, migraciones y tests. La lÃ³gica de negocio (usuarios, dispositivos, heartbeats, experiencias, contenido, programaciones, comunicaciÃ³n con dispositivos) se incorporarÃ¡ en etapas posteriores.

## Flujo de trabajo (PC + servidor)

- **PC**: ediciÃ³n de cÃ³digo en la carpeta sincronizada (Syncthing). No se ejecuta nada aquÃ­.
- **Servidor**: recibe los cambios por sincronizaciÃ³n y ejecuta todo (instalaciÃ³n, tests, migraciones, Docker, servidor de aplicaciÃ³n), conectÃ¡ndose por SSH.
- **PC (pruebas)**: acceso por red local a `http://<IP_SERVIDOR>:8000`.

> El `.stignore` excluye de la sincronizaci�n `.venv`, caches de Python, `postgres_data`, los builds de Flutter y el `.env` real. **Debe vivir en la ra�z de la carpeta compartida de Syncthing**: `D:\\CauceStream\\.stignore` (la carpeta compartida del proyecto es `D:\\CauceStream`, folder `cauce-stream`; `D:\\Maker-sync` no se usa para el proyecto). Se sincroniza entre dispositivos. Pr�ctica m�s robusta: crear el venv fuera de la carpeta sincronizada (p. ej. `D:\\venvs\cauce`).

## Stack

- Python 3.12+
- FastAPI + Uvicorn
- Pydantic v2 / Pydantic Settings
- SQLAlchemy 2.x (async, asyncpg)
- PostgreSQL
- Alembic
- pytest + httpx

## Estructura

```
backend/
â”œâ”€â”€ app/
â”‚   â”œâ”€â”€ main.py            # Entry point, creaciÃ³n de la app
â”‚   â”œâ”€â”€ core/              # ConfiguraciÃ³n, BD, logging, excepciones
â”‚   â”œâ”€â”€ api/               # Routers y dependencias HTTP
â”‚   â”‚   â””â”€â”€ routes/
â”‚   â”œâ”€â”€ schemas/           # Modelos Pydantic (entrada/salida de API)
â”‚   â”œâ”€â”€ models/            # Modelos ORM SQLAlchemy (futuro)
â”‚   â”œâ”€â”€ repositories/      # Acceso a datos (futuro)
â”‚   â”œâ”€â”€ services/          # LÃ³gica de negocio (futuro)
â”‚   â””â”€â”€ utils/
â”œâ”€â”€ alembic/               # Migraciones
â”œâ”€â”€ tests/                 # pytest
â”œâ”€â”€ .env.example
â”œâ”€â”€ alembic.ini
â”œâ”€â”€ Dockerfile
â”œâ”€â”€ docker-compose.yml
â”œâ”€â”€ requirements.txt
â””â”€â”€ requirements-dev.txt
```

SeparaciÃ³n de responsabilidades: `api` (HTTP) â†’ `services` (negocio) â†’ `repositories` (datos) â†’ `models` (ORM). Los endpoints no contienen lÃ³gica de negocio ni SQL directo.

## Requisitos (en el servidor)

- Docker + Docker Compose (recomendado, incluye PostgreSQL), **o**
- Python 3.12+ y PostgreSQL nativos

## OpciÃ³n A: Docker (recomendado)

Desde SSH, en `backend/`:

```bash
docker compose up --build -d
```

Levanta dos servicios:

- `db`: PostgreSQL 16 (usuario/contraseÃ±a/base: `cauce`)
- `backend`: Uvicorn en `0.0.0.0:8000`; ejecuta `alembic upgrade head` antes de arrancar (sin efecto hasta que existan migraciones)

Ver logs o parar:

```bash
docker compose logs -f backend
docker compose down            # (aÃ±adir -v para borrar tambiÃ©n el volumen de la BD)
```

Desde la PC: `http://<IP_SERVIDOR>:8000/docs`.

## OpciÃ³n B: entorno virtual en el servidor (Windows)

```powershell
# Por SSH en el servidor
cd D:\CauceStream\backend

python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
```

Si PowerShell bloquea la activaciÃ³n: `Set-ExecutionPolicy -Scope Process RemoteSigned`.

### ConfiguraciÃ³n (.env)

El `.env` no se sincroniza: crearlo en el servidor a partir del ejemplo:

```bash
cp .env.example .env
```

Variables principales:

| Variable       | DescripciÃ³n                                          | Ejemplo                                              |
|----------------|------------------------------------------------------|------------------------------------------------------|
| `DATABASE_URL` | URL de PostgreSQL con driver asyncpg                | `postgresql+asyncpg://cauce:cauce@localhost:5432/cauce` |
| `APP_ENV`      | `development` \| `testing` \| `production`           | `development`                                        |
| `DEBUG`        | Modo debug de FastAPI                                | `true`                                               |
| `CORS_ORIGINS` | OrÃ­genes permitidos, separados por coma (vacÃ­o = off)| `http://localhost:3000`                              |
| `LOG_LEVEL`    | Nivel de logging                                     | `INFO`                                               |

Con la OpciÃ³n A la base de datos puede reutilizarse desde el host: si `db` corre por Docker, `DATABASE_URL` con host `localhost` funciona en el servidor.

### Ejecutar el backend

```bash
uvicorn app.main:app --host 0.0.0.0 --reload
```

`--host 0.0.0.0` es imprescindible para que sea alcanzable desde la PC. `--reload` solo para desarrollo.

Endpoints:

- `GET /` â†’ respuesta mÃ­nima indicando que el backend funciona
- `GET /api/health` â†’ `{"status": "ok"}`
- `GET /docs` â†’ documentaciÃ³n interactiva (Swagger UI)
- `GET /redoc` â†’ documentaciÃ³n (ReDoc)

Si la PC no conecta: verificar el firewall del servidor (p. ej. permitir el puerto 8000 en el Firewall de Windows: `New-NetFirewallRule -DisplayName "Cauce 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow`).

### SoluciÃ³n de problemas (servidor Windows)

- **`failed to connect to the docker API at npipe:////./pipe/docker_engine`**: el daemon no estÃ¡ corriendo. Abrir Docker Desktop (o `Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"`) y esperar a que `docker info` responda.
- **`error getting credentials ... A specified logon session does not exist`** en cada pull de docker.io: el backend de Docker Desktop consulta el Administrador de credenciales de Windows al tirar de Docker Hub; si Docker Desktop se arrancÃ³ desde una sesiÃ³n SSH (no interactiva), no puede acceder a Ã©l. No depende del `config.json` del CLI. SoluciÃ³n sin tocar el proyecto: tirar del mirror pÃºblico de Amazon (anÃ³nimo) y reetiquetar:

  ```powershell
  docker pull public.ecr.aws/docker/library/postgres:16-alpine
  docker pull public.ecr.aws/docker/library/python:3.12-slim
  docker tag public.ecr.aws/docker/library/postgres:16-alpine postgres:16-alpine
  docker tag public.ecr.aws/docker/library/python:3.12-slim python:3.12-slim
  ```

  SoluciÃ³n de fondo (requiere acceso grÃ¡fico una Ãºnica vez): inicio de sesiÃ³n automÃ¡tico + "Start Docker Desktop when you sign in", para que Docker Desktop corra en la sesiÃ³n interactiva del usuario.
- **El daemon tras un reinicio del servidor**: Docker Desktop arranca con la sesiÃ³n del usuario. Habilitar "Start Docker Desktop when you sign in" en Docker Desktop (Settings â†’ General) para que el stack se levante al iniciar sesiÃ³n.

### Tests

```bash
pytest
```

### Migraciones (Alembic)

TodavÃ­a no hay tablas de negocio; los comandos quedan preparados para cuando existan los modelos.

```bash
# Generar una migraciÃ³n a partir de los modelos
alembic revision --autogenerate -m "descripcion"

# Aplicar migraciones pendientes
alembic upgrade head

# Revertir Ãºltima migraciÃ³n
alembic downgrade -1
```

La URL de la base de datos se toma de la configuraciÃ³n central (`app/core/config.py`), no se duplica en `alembic.ini`. Nota: las revisiones autogeneradas conviene generarlas desde la carpeta donde se edita el cÃ³digo o en el servidor tras sincronizar; el archivo de migraciÃ³n resultante se sincroniza como cualquier cÃ³digo.

## MÃ³dulo: usuarios, roles y permisos

Primer mÃ³dulo funcional. AutenticaciÃ³n JWT local (sin proveedores externos, apto para LAN) y autorizaciÃ³n basada en permisos.

### Endpoints

| MÃ©todo | Ruta | Permiso requerido |
|---|---|---|
| POST | `/api/auth/login` | â€” (pÃºblico) |
| POST | `/api/users` | gestiÃ³n del rol objetivo (`users.mediators.manage` / `users.admins.manage`) |
| GET | `/api/users` | `users.view` |
| GET | `/api/users/{id}` | `users.view` |
| PATCH | `/api/users/{id}` | gestiÃ³n del rol resultante |
| POST | `/api/users/{id}/activate` Â· `/deactivate` | gestiÃ³n del rol del usuario |
| GET | `/api/roles` Â· `/api/permissions` | `users.view` |
| GET | `/api/roles/{name}/permissions` | `users.view` |
| PUT | `/api/roles/{name}/permissions` | `roles.permissions.manage` |

### Modelo de autorizaciÃ³n

- Roles fijos de dominio: `ADMINISTRADOR` y `MEDIADOR` (sin CRUD de roles; se crean por seed idempotente al arrancar).
- ADMINISTRADOR recibe todos los permisos; MEDIADOR solo los `*.view` de dispositivos, experiencias, contenido y programaciones.
- Los permisos son un catÃ¡logo editable: un administrador puede reasignar los permisos de un rol vÃ­a `PUT /api/roles/{name}/permissions` (reemplazo completo; el seed nunca revierte cambios hechos por API).
- La autorizaciÃ³n se expresa siempre como permisos (`require_permission("...")`), nunca como comparaciones de nombre de rol.
- CÃ³digos de respuesta: `401` no autenticado, `403` sin permiso o cuenta desactivada, `409` email duplicado, `404` no existe.
- `password_hash` nunca se devuelve en ninguna respuesta.
- **ContraseÃ±as = PIN numÃ©rico de 4 dÃ­gitos** (polÃ­tica de Cauce para acceso rÃ¡pido en la sala). El formato se valida igual en login, creaciÃ³n y actualizaciÃ³n; los ceros a la izquierda se respetan (`0042`).

### Primer acceso

El seed crea un administrador inicial solo cuando no existe ninguno, con las credenciales de `BOOTSTRAP_ADMIN_EMAIL` / `BOOTSTRAP_ADMIN_PASSWORD` del `.env` (PIN por defecto `0000`). **Cambia su PIN tras el primer inicio de sesiÃ³n** (PATCH `/api/users/{id}` con tu propio usuario).

## MÃ³dulo: dispositivos y heartbeats

Los dispositivos cliente (pantallas, PCs, Android, Raspberry Pi, VR, o cualquier cliente que implemente el contrato) se registran, reportan heartbeat y el servidor determina su estado. El backend es completamente agnÃ³stico del origen del heartbeat: un dispositivo real y un simulador que envÃ­en el mismo payload producen el mismo comportamiento.

### Conceptos del modelo

| Campo | Significado |
|---|---|
| `device_uid` | Identidad estable y Ãºnica del dispositivo. Se registra **tal como lo expone el dispositivo** (autoconfiguraciÃ³n): puede contener espacios y caracteres arbitrarios y nunca se normaliza (solo lÃ­mite de 100 caracteres). La IP/puerto son informaciÃ³n dinÃ¡mica; nunca identidad. El heartbeat lo recibe en la ruta, URL-encoded (p. ej. `/api/devices/SALA%20PANTALLA%201/heartbeat`). |
| `status` | Conectividad, determinada **por el servidor**: `online` si hay heartbeat vÃ¡lido reciente; `offline` si pasan mÃ¡s de `DEVICE_OFFLINE_AFTER_SECONDS` (30 s) sin heartbeats. El cliente nunca lo reporta. |
| `device_state` | Estado operativo reportado por el cliente: `active` (en uso / pantalla encendida) / `idle` (en espera / pantalla apagada o suspendida). Generaliza dispositivos con y sin pantalla. **Independiente de `status`**: un dispositivo `idle` sigue enviando heartbeats y permanece `online`. |
| `current_media` | Medio que el dispositivo **reporta estar reproduciendo**: el `id` numÃ©rico de un medio de la biblioteca, como texto (ej. `"5"`), o `"unknown"` cuando el heartbeat no reporta un identificador vÃ¡lido. Se envÃ­a dentro de `payload.current_media` (opcional). Ausente, nulo o no identificador â†’ `"unknown"`; nunca se conserva el valor previo ni se infiere de otros campos. El atributo retirado `current_application` (nombre de aplicaciÃ³n) **no** se interpreta como medio: los clientes antiguos pueden seguir enviÃ¡ndolo sin romper nada (pasa como dato inerte). |
| `payload` | Atributos dinÃ¡micos **especÃ­ficos del dispositivo** (JSON): medio actual, puerto, baterÃ­a, carga, etc. Opcional y extensible; los atributos conocidos se validan si estÃ¡n presentes (`current_media` id de medio, `port` 1-65535, `battery_level` 0-100, `is_charging` booleano, `power_source` texto) y los desconocidos se aceptan tal cual. Se fusiona por clave: un atributo ausente **nunca** se interpreta como `false`/`0`/`null` ni borra el valor previo (excepciÃ³n: `current_media`, explÃ­cito en su fila). Las claves reservadas (campos generales, incluido el nombre retirado `display_state`, y datos controlados por el servidor) se rechazan con `422`. Los cambios de payload no generan eventos (mÃ©tricas como la baterÃ­a cambian en cada heartbeat). |
| `last_seen` | Marca de tiempo (UTC) del Ãºltimo heartbeat vÃ¡lido. Se actualiza con **cada** heartbeat, aunque nada cambie. |

### Endpoints

| MÃ©todo | Ruta | Permiso |
|---|---|---|
| POST | `/api/devices` | `devices.manage` |
| POST | `/api/devices/autoconfig` | `devices.manage` |
| GET | `/api/devices/autoconfig/pending` | `devices.manage` |
| GET | `/api/devices` | `devices.view` |
| GET | `/api/devices/{device_uid}` | `devices.view` |
| DELETE | `/api/devices/{device_uid}` | `devices.manage` |
| GET | `/api/devices/{device_uid}/events` | `devices.view` |
| POST | `/api/devices/{device_uid}/heartbeat` | â€” (protocolo de dispositivos, sin usuario) |

Reglas: el registro deja el dispositivo `offline` (solo un heartbeat lo pone `online`); un heartbeat de un `device_uid` no registrado devuelve `404` y **no** crea el dispositivo (flujo: registro â†’ heartbeat); la IP del payload es la direcciÃ³n que el dispositivo declara (no se usa la IP de origen de la conexiÃ³n); el puerto vive dentro de `payload` (no todos los dispositivos tienen uno y su ausencia no es error); `current_media` tambiÃ©n vive dentro de `payload` (ver su fila). `DELETE /api/devices/{device_uid}` (204) elimina el dispositivo **y todo su historial de eventos** en cascada; es pura desregistro: tras el borrado, un heartbeat de ese uid se comporta como dispositivo desconocido (`404`, o nuevo descubrimiento si la autoconfiguraciÃ³n estÃ¡ activa) y nunca se recrea automÃ¡ticamente.

### AutoconfiguraciÃ³n (descubrimiento de dispositivos)

La autoconfiguraciÃ³n permite descubrir dispositivos a partir de sus heartbeats. Nunca registra nada automÃ¡ticamente: el registro definitivo lo hace un administrador con el endpoint existente `POST /api/devices`.

- `POST /api/devices/autoconfig` con `{"enabled": true|false}` activa o desactiva el modo. **Desactivado por defecto y tras cada reinicio del backend** (reset en el arranque). El estado vive en PostgreSQL (`autoconfig_state`), no en memoria: todos los workers/instancias ven el mismo modo. Al desactivar se limpia la lista de pendientes.
- Con el modo activado, un heartbeat de un `device_uid` no registrado se acepta con **`202 Accepted`** y `{"device_uid", "status": "pending_registration", "last_seen"}`: sus datos se conservan temporalmente (`device_uid`, `ip_address`, `device_state`, `payload`, `last_seen`) sin crear filas de inventario. Con el modo desactivado se mantiene el `404` actual. Los dispositivos registrados se procesan con normalidad independientemente del modo.
- `GET /api/devices/autoconfig/pending` devuelve los dispositivos detectados que enviaron heartbeat en los Ãºltimos `AUTOCONFIG_PENDING_TTL_SECONDS` (30 s, configurable). La caducidad depende solo de la ausencia de heartbeats. Formato (sin `payload`, sin duplicados, sin registrados):

```json
{"devices": [{"device_uid": "tablet-ar-01", "ip_address": "10.15.1.164", "device_state": "active", "last_seen": "2026-10-19T16:30:00Z"}]}
```

- Registro definitivo: el frontend selecciona un pendiente y envÃ­a el `device_uid` con la IP confirmada mediante el formulario del endpoint existente; el backend valida duplicados incluso bajo concurrencia (restricciÃ³n Ãºnica). Tras un registro exitoso el dispositivo desaparece de pendientes.

### Ejemplos

Registro:

```json
POST /api/devices
{"device_uid": "CAUCE-001", "name": "Pantalla 1", "type": "screen", "ip_address": "10.15.1.151", "port": 8001}
```

Heartbeat (campos generales + `payload` opcional con atributos del dispositivo; el cliente no puede reportar `status`):

```json
POST /api/devices/CAUCE-001/heartbeat
{
  "ip_address": "10.15.1.151",
  "device_state": "active",
  "payload": {
    "current_media": 5,
    "port": 8000,
    "battery_level": 78,
    "is_charging": false
  }
}
```

Respuesta:

```json
{"device_uid": "CAUCE-001", "status": "online", "device_state": "active", "current_media": "5", "payload": {"port": 8000, "battery_level": 78, "is_charging": false}, "last_seen": "2026-10-07T21:00:00Z"}
```

### Historial de eventos (`device_events`)

Solo se registran **cambios** (heartbeats idÃ©nticos no generan historial): `device_registered`, `status_changed`, `device_state_changed`, `media_changed`, `ip_changed`, `port_changed` â€” cada uno con `previous_value`/`new_value`. El `port_changed` y el `media_changed` se derivan de `payload.port` / `payload.current_media` cuando el dispositivo los reporta. La detecciÃ³n de offline la hace una tarea interna del servidor (barrido periÃ³dico, sin brokers externos): `online â†’ offline` genera un Ãºnico `status_changed`; barridos repetidos sin recuperaciÃ³n no generan eventos; al volver un heartbeat se registra `offline â†’ online`.

Nota sobre validaciÃ³n por tipo: el modelo registra `type` como texto libre y todavÃ­a no existe una correspondencia tipo â†’ esquema de payload, por lo que los atributos conocidos (`current_media`, `port`, `battery_level`, `is_charging`, `power_source`) se validan de forma universal. La modificaciÃ³n mÃ­nima futura para validar por tipo serÃ­a un registro `type â†’ schema` aplicado en `DeviceService.heartbeat` tras obtener el dispositivo.

## MÃ³dulo: medios audiovisuales (RF-008, fase 1)

CreaciÃ³n y gestiÃ³n de medios: imÃ¡genes y videos se cargan como archivo real (`multipart/form-data`) y se guardan en el disco del servidor; las URLs externas se registran con sus metadatos sin descargar nada. Los metadatos viven en PostgreSQL (`media`); los binarios en el directorio configurado. La asignaciÃ³n a dispositivos se describe en el mÃ³dulo siguiente; reproducciÃ³n y tiempo real quedan fuera.

### Conceptos

| Campo | Significado |
|---|---|
| `name` | Nombre visible. En cargas es el nombre original del archivo (o el indicado en el form); **nunca** se usa como ruta fÃ­sica. |
| `media_type` | `image` \| `video` \| `url`. |
| `mime_type` | Tipo MIME persistido. En cargas es el canÃ³nico de la extensiÃ³n validada; opcional en URLs. |
| `file_size` | Bytes del archivo (solo cargas). |
| `storage_key` | Clave relativa y estable (`images/<uuid>.png`, `videos/<uuid>.mp4`); la ruta fÃ­sica se resuelve con la configuraciÃ³n vigente. Las URLs no tienen clave. |
| `external_url` | DirecciÃ³n http/https registrada tal cual (solo `url`). El backend **nunca** la descarga ni la sigue. |

### Endpoints

| MÃ©todo | Ruta | Permiso |
|---|---|---|
| POST | `/api/media` (multipart: `media_type`, `file`, `name?`) | `content.manage` |
| POST | `/api/media/urls` (JSON: `name`, `url`, `mime_type?`) | `content.manage` |
| GET | `/api/media?limit=&offset=` | `content.view` |
| GET | `/api/media/{id}` | `content.view` |
| GET | `/api/media/{id}/file` | `content.view` |
| DELETE | `/api/media/{id}` | `content.manage` |

La creaciÃ³n se divide en dos operaciones con contratos explÃ­citos: `POST /api/media` solo acepta `multipart/form-data` para `image`/`video`; `POST /api/media/urls` acepta JSON para URLs externas. `GET /{id}/file` sirve el binario (`Content-Type` = MIME persistido, `inline`) con el nombre original en `Content-Disposition`; los medios `url` devuelven `404` en esa ruta.

### ValidaciÃ³n e integridad

- Extensiones permitidas por tipo (image: png/jpg/jpeg/gif/webp; video: mp4/webm/ogg/mov/mkv). El MIME declarado debe corresponder a la extensiÃ³n (se tolera `application/octet-stream`). TamaÃ±os: `413` si supera `CAUCE_MEDIA_MAX_SIZE_MB` (200 por defecto).
- Nombres de almacenamiento Ãºnicos por UUID; el nombre original queda solo como metadato. Sin traversal: toda clave resuelta se verifica dentro del directorio raÃ­z de medios.
- Escritura atÃ³mica (`.part` + rename): un fallo nunca deja archivos parciales. Si PostgreSQL falla tras guardar el archivo, el archivo se limpia; si la escritura falla, no se crea registro. Al eliminar, el archivo solo se borra despuÃ©s de verificar que pertenece a ese registro y una vez eliminado el registro.
- Las URLs aceptan Ãºnicamente esquemas `http`/`https`.

### Almacenamiento (configuraciÃ³n)

`CAUCE_MEDIA_DIR` define la raÃ­z de los binarios. Absoluta se usa tal cual; relativa se resuelve contra la raÃ­z del proyecto backend; **vacÃ­a usa el default estable `backend/data/media`**, calculado respecto al paquete `app`, no del directorio desde el que se invoque `uvicorn` (los archivos sobreviven reinicios y quedan fuera de directorios temporales, fÃ¡ciles de inspeccionar en Windows). El directorio se crea al escribir.

- **Desarrollo local (Windows, venv + uvicorn)**: no configurar nada (default `backend\data\media`) o poner una ruta absoluta en `.env`.
- **Docker**: `CAUCE_MEDIA_DIR=/app/data/media` con el volumen `media_data:/app/data/media` ya declarado en `docker-compose.yml`; los binarios sobreviven a la recreaciÃ³n del contenedor mientras el volumen persista. No hay que hacer coincidir rutas de Windows dentro del contenedor.

### Ejemplos

```bash
# Subir una imagen
curl -X POST $API/api/media -H "Authorization: Bearer $TOKEN" \
  -F "media_type=image" -F "name=Portada" -F "file=@portada.png"

# Registrar una URL externa
curl -X POST $API/api/media/urls -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"name":"Loop YouTube","url":"https://example.com/x"}'

# Listar con paginaciÃ³n, ver el archivo, eliminar
curl -H "Authorization: Bearer $TOKEN" "$API/api/media?limit=20&offset=0"
curl -H "Authorization: Bearer $TOKEN" -o portada.png "$API/api/media/1/file"
curl -X DELETE -H "Authorization: Bearer $TOKEN" "$API/api/media/1"
```

Persistencia tras reinicio: la prueba `test_file_survives_service_restart` verifica que una instancia nueva de configuraciÃ³n resuelve la misma ruta fÃ­sica para la misma clave; el procedimiento manual es subir un archivo, reiniciar uvicorn y volver a pedir `GET /api/media/{id}/file`.

## MÃ³dulo: asignaciÃ³n de medios a dispositivos (RF-008)

Distingue el medio que la **administraciÃ³n asigna** a un dispositivo del medio que el dispositivo **reporta estar reproduciendo** (`current_media`). Ambos se comparan con una Ãºnica regla central (`assignment_service.compute_sync_status`): ids iguales â†’ `synchronized`; distinto id, `"unknown"` o nunca reportado â†’ `pending`. SincronizaciÃ³n no implica reproducciÃ³n exitosa: el protocolo actual solo reporta el identificador del medio.

| MÃ©todo | Ruta | Permiso |
|---|---|---|
| PUT | `/api/devices/{device_uid}/assignment` (JSON `{"media_id": int}`) | `content.manage` |
| GET | `/api/assignments` | `content.view` |

Reglas:

- La asignaciÃ³n valida que el dispositivo y el medio existen (`404` en otro caso). El cliente identifica el medio por su **id numÃ©rico** (`payload.current_media` en el heartbeat): nunca se comparan nombres de archivo con ids.
- MÃ¡ximo **una asignaciÃ³n vigente por dispositivo** (`device_id` Ãºnico): asignar otro medio **actualiza** la fila existente, no crea asignaciones activas concurrentes.
- El estado se recalcula al asignar y en **cada heartbeat** (misma transacciÃ³n que la actualizaciÃ³n de `current_media`): en cuanto el dispositivo reporta el id asignado pasa a `synchronized`; si reporta otro id o `"unknown"`, vuelve a `pending`.
- Un dispositivo sin asignaciÃ³n vigente late con normalidad.
- Respuesta de `GET /api/assignments`: una fila por dispositivo asignado con `{id, device_id, device_uid, media_id, media_name, sync_status, revision, created_at, updated_at}` (una Ãºnica consulta con joins, sin N+1).
- Fuera de esta fase: programaciÃ³n horaria, listas de reproducciÃ³n, envÃ­o de Ã³rdenes por WebSocket y reproducciÃ³n.

## Seguridad: clave compartida de dispositivos

Los endpoints del **protocolo de dispositivos** (sin usuario) se protegen con un secreto compartido entre el servidor y todos los clientes Cauce Stream: `CAUCE_DEVICE_SECRET` (variable de entorno; el mismo valor en el servidor y en el `.env` de cada cliente). El cliente lo envÃ­a en el header **`X-Device-Key`**.

Endpoints protegidos:

| Endpoint | Comportamiento con clave vÃ¡lida |
|---|---|
| `POST /api/devices/{uid}/heartbeat` | `200`/`202`; sin clave o clave errÃ³nea â†’ `401 {"code": "device_key_invalid"}` |
| `WS /api/devices/{uid}/ws` | handshake aceptado; sin clave/errÃ³nea â†’ cierre `1008` "Invalid device key" |
| `GET /api/media/{id}/file` | descarga del medio (asÃ­ el cliente obtiene los archivos asignados sin usuario) |

Reglas:

- **Doble vÃ­a en la descarga de medios**: `X-Device-Key` vÃ¡lido **o** token de usuario con `content.view`. El resto de endpoints de administraciÃ³n (listar, subir, asignar, usuarios, etc.) ignoran la clave de dispositivo y siguen exigiendo permisos de usuario: la clave nunca eleva privilegios administrativos.
- **Modo transiciÃ³n**: si `CAUCE_DEVICE_SECRET` estÃ¡ vacÃ­a, la autenticaciÃ³n de dispositivos queda deshabilitada (todo funciona como hoy) y el arranque registra un warning. Al definirla, cada cliente debe enviar el mismo valor o serÃ¡ rechazado (`401`/cierre `1008`).
- La comparaciÃ³n es de tiempo constante y la clave jamÃ¡s se registra en logs.
- RotaciÃ³n: cambiar el valor en el servidor y en todos los clientes a la vez (clave compartida, no por dispositivo; la identidad por dispositivo llegarÃ¡ en una fase posterior si se necesita).

En el cliente (Flutter, `client/.env`): `CAUCE_DEVICE_SECRET=<mismo valor>`; el servicio de heartbeat lo envÃ­a automÃ¡ticamente en `X-Device-Key`.

## MÃ³dulo: notificaciones de reproducciÃ³n por WebSocket

Canal de control servidor â†’ dispositivo para entregar la asignaciÃ³n vigente. **No sustituye al heartbeat**: la conectividad (`online`/`offline`) y el medio reproducido (`current_media`) siguen determinÃ¡ndose exclusivamente por heartbeats. ConexiÃ³n (desde la LAN): `ws://<IP_SERVIDOR>:8000/api/devices/<device_uid>/ws` â€” sin credenciales de usuario (protocolo de dispositivos, igual que el heartbeat; la autenticaciÃ³n de dispositivos llegarÃ¡ con la fase de seguridad). Solo dispositivos registrados: si el uid no existe, el handshake se rechaza (`close 1008`, "Device not registered").

### Flujo

```
admin: PUT /api/devices/{uid}/assignment â”€â”€â–º commit PostgreSQL â”€â”€â–º playback.command (si conectado)
dispositivo: WS connect â”€â”€â–º playback.sync (asignaciÃ³n vigente persistida, o assignment: null)
```

1. Al conectar, el servidor envÃ­a `playback.sync` con el estado **persistido** en ese momento: la asignaciÃ³n vigente o `assignment: null` (sin asignaciÃ³n, mensaje inequÃ­voco). Independiente de los mensajes perdidos: todo se reconstruye desde PostgreSQL al reconectarse (tambiÃ©n tras reiniciar el backend).
2. Al asignar, el backend **persiste primero** (commit) y notifica despuÃ©s con `playback.command`. Si el dispositivo estÃ¡ desconectado, la asignaciÃ³n queda guardada y se entrega en la prÃ³xima conexiÃ³n vÃ­a `playback.sync`.
3. `revision` es **monÃ³tona por dispositivo** (persistida en la asignaciÃ³n): 1 en la primera asignaciÃ³n, +1 en cada cambio. Regla del cliente: aplicar solo Ã³rdenes con `revision` mayor que la Ãºltima aplicada; una orden antigua jamÃ¡s sustituye el estado mÃ¡s reciente (el servidor tampoco encola Ã³rdenes: siempre envÃ­a el Ãºltimo estado confirmado).
4. Enviar el mensaje **no marca nada como reproducido**: `sync_status` solo cambia por la comparaciÃ³n central (heartbeat con `current_media`).

### Mensajes del servidor (protocolo versiÃ³n 1)

`playback.sync` (al conectar; sin asignaciÃ³n):

```json
{"type": "playback.sync", "protocol": 1, "device_uid": "SALA 1", "assignment": null, "sent_at": "2026-10-19T18:00:00Z"}
```

`playback.sync` / `playback.command` con asignaciÃ³n (el comando se envÃ­a en cada cambio confirmado):

```json
{
  "type": "playback.command",
  "protocol": 1,
  "device_uid": "SALA 1",
  "assignment": {
    "assignment_id": 3,
    "media_id": 5,
    "revision": 2,
    "sync_status": "pending",
    "media": {
      "name": "portada.png",
      "media_type": "image",
      "mime_type": "image/png",
      "file_size": 20480,
      "file_url": "/api/media/5/file",
      "external_url": null
    }
  },
  "sent_at": "2026-10-19T18:00:00Z"
}
```

- `media_type` distingue `image` / `video` / `url`.
- `file_url` es el **endpoint de descarga existente** (`/api/media/{id}/file`, relativo) solo para `image`/`video`; para `url` se entrega `external_url` y `file_url: null`. No se inventan URLs. Nota de autenticaciÃ³n: ese endpoint hoy exige permiso `content.view` (token de usuario); hasta la fase de seguridad de dispositivos, un cliente-dispositivo no puede descargar con ese endpoint sin credenciales.
- `sync_status` es el estado persistido en ese instante (`synchronized` | `pending`).

### Mensajes del cliente (opcional, solo confirmaciones)

```json
{"type": "playback.ack", "assignment_id": 3, "revision": 2}
{"type": "playback.error", "assignment_id": 3, "revision": 2, "error": {"code": "download_failed", "message": "..."}}   // code â‰¤ 50, message â‰¤ 500
```

- Se validan contra la **Ãºltima orden de ese mismo dispositivo** (`assignment_id` + `revision`): confirmaciones obsoletas o de otra asignaciÃ³n se ignoran (un cliente no puede referenciar asignaciones ajenas; la conexiÃ³n estÃ¡ ligada al uid de su ruta).
- **Efecto exacto: ninguno sobre el estado.** Se registran en el log; jamÃ¡s modifican `current_media` ni `sync_status`.
- Mensajes malformados/desconocidos se ignoran sin cerrar la conexiÃ³n. TamaÃ±o mÃ¡ximo entrante: 8 KB; sobrepasarlo cierra con `1009`.

### GestiÃ³n de conexiones y robustez

- Una conexiÃ³n por dispositivo (identificada por `device_uid`). ConexiÃ³n duplicada: **gana la mÃ¡s nueva**; la anterior se cierra con `4000` ("Replaced by a newer connection").
- El gestor vive **en memoria del proceso** (sin Redis/brokers para el MVP): las notificaciones en tiempo real requieren ejecutar el backend en **un Ãºnico proceso/worker de uvicorn**; las conexiones no se comparten entre workers. PostgreSQL permite reconstruir el estado tras cualquier reinicio (`playback.sync`).
- EnvÃ­os aislados por cliente: un fallo de envÃ­o o desconexiÃ³n abrupta limpia esa conexiÃ³n y nunca interrumpe las solicitudes HTTP ni los heartbeats. El bucle de recepciÃ³n nunca bloquea el event loop.
- **Watchdog de ACK:** todo `playback.command` entregado a un socket arma un temporizador de 10 s correlacionado con (socket, `assignment_id`, `revision`). Un `playback.ack` o `playback.error` que coincida con esa orden exacta lo cancela; un ACK de una orden anterior NO cancela el de la posterior. Al expirar, el servidor cierra ese socket con `4001` ("Playback ACK timeout") y lo retira del inventario del canal: `ws_connected` vuelve a reflejar la realidad y el cliente recupera el estado persistido en su prÃ³xima reconexiÃ³n (`playback.sync`). El ACK solo alimenta el watchdog: jamÃ¡s modifica `current_media` ni `sync_status`.
- CÃ³digos de cierre: `1008` (dispositivo no registrado), `1009` (mensaje excesivo), `4000` (reemplazado), `4001` (timeout de ACK), `1000` (desconexiÃ³n normal).
- **Keepalive de infraestructura:** uvicorn debe correr con sus pings WS por defecto (`--ws-ping-interval 20 --ws-ping-timeout 20`, implementaciÃ³n `websockets`). Verificar en el servidor cÃ³mo se lanza realmente el proceso antes de asumirlo:

  ```powershell
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Select-Object ProcessId, CommandLine
  ```

  En operaciÃ³n **no usar `--reload`**: la carpeta se sincroniza con Syncthing y cada cambio de archivo reiniciarÃ­a la app, cortando todos los canales WS.

### Tarea pendiente (fuera del alcance del blindaje del canal)

**Reintento de reproducciÃ³n fallida con la misma revisiÃ³n.** El cliente acepta una orden encolÃ¡ndola en su `RevisionGate` ANTES de aplicarla; si la aplicaciÃ³n falla tras aceptarla (p. ej. descarga caÃ­da), ni el `playback.sync` de una reconexiÃ³n ni el watchdog la reintentan, porque la misma revisiÃ³n ya fue aceptada. La recuperaciÃ³n hoy requiere un cambio de asignaciÃ³n (nueva revisiÃ³n). SoluciÃ³n futura a diseÃ±ar por separado (p. ej. orden de re-sincronizaciÃ³n explÃ­cita o reintento dirigido por el servidor); NO debe resolverse dentro del watchdog de ACK.

### Probarlo

```bash
# con el backend corriendo (uvicorn, 1 worker):
wscat -c ws://<IP_SERVIDOR>:8000/api/devices/SALA%201/ws
# 1) recibe playback.sync de inmediato
# 2) en otra terminal, asignar un medio (token de admin):
curl -X PUT $API/api/devices/SALA%201/assignment -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"media_id": 5}'
# 3) wscat recibe playback.command
# 4) confirmar recepciÃ³n:  {"type":"playback.ack","assignment_id":3,"revision":2}
```

(El uid va URL-encoded en la ruta, igual que en el heartbeat.)

## PrÃ³ximas etapas

Sobre este esqueleto se aÃ±adirÃ¡n: dispositivos cliente, estado/disponibilidad, heartbeats, configuraciÃ³n de dispositivos, experiencias de la Sala Cauce, distribuciÃ³n y reproducciÃ³n de contenido, programaciones y comunicaciÃ³n servidor-dispositivos.
