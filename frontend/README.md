# CauceStream — Frontend Flutter

Aplicacion movil de administracion y operacion de la **Sala Cauce**
(CCFJC). Cliente del backend FastAPI que corre en el nodo central de
la LAN de la sala (`10.15.0.0/16`, servidor en `10.15.1.150`).

Las referencias visuales (`docs/html_reference/`) y los assets
originales (`assets/`) se conservan sin cambios.

## Fase 1 — alcance

- Proyecto Flutter funcional y organizado.
- **Login** integrado al contrato real: `POST /api/auth/login`
  (`{email, password}` con PIN de 4 digitos) →
  `{access_token, token_type}`. JWT almacenado en el almacenamiento
  seguro del dispositivo.
- **Perfil** integrado dentro de los contratos disponibles (ver
  "Limitaciones").
- **Pantallas base** (solo interfaz y navegacion, sin logica de
  negocio): Inicio, Dispositivos, Detalle de dispositivo, Registro de
  dispositivo, Biblioteca de medios, Detalle de medio, Registro de
  medio, Actividades y alertas.
- Navegacion: shell de 5 pestañas (Inicio, Dispositivos, Biblioteca,
  Actividad, Mas → Perfil) con guard de sesion.

## Biblioteca de medios — data real (fase actual)

La biblioteca es una vista de **administracion**: la app no reproduce
ni descarga medios (la reproduccion vive en el cliente de la sala).
Lo importante es la informacion real de cada recurso del servidor y
una previsualizacion pequeña cuando existe.

Integrado contra los seis endpoints de medios del backend (ver
"Contratos"):

- **Listado** paginado (`GET /api/media?limit=&offset=`, pagina de
  50, "cargar mas", pull-to-refresh) con `MediaLibraryController`.
  Cada tarjeta muestra la jerarquia de datos real: **nombre** →
  **tipo** (imagen/video/URL) → **tamano legible** (`readableSize`,
  o "Recurso externo" para URLs) → **fecha** en formato local corto.
- **Miniaturas reales de imagenes** en el listado via
  `GET /api/media/{id}/file` (con `Authorization`; por eso baja por
  `ApiClient`, nunca `Image.network`). Se re-escalan a resolucion de
  miniatura (400 px) y se cachean en disco con limite (abajo).
- **Detalle** (`GET /api/media/{id}`) con metadatos completos (MIME
  incluido) y vista previa de imagen (1080 px, mismo cache de disco).
- **Subida** multipart (`POST /api/media` con `file_picker`) y
  registro de URLs (`POST /api/media/urls`), con validacion previa,
  progreso y errores especificos (abajo).
- **Borrado** (`DELETE /api/media/{id}`, 204) con confirmacion; al
  eliminar se limpian las miniaturas del medio del cache.

### Cache de miniaturas (`ThumbnailService`)

- **Clave de invalidacion**: `id + updated_at` (y destino:
  tarjeta/detalle). Si el medio se reemplaza, cambia su `updated_at`
  y la clave nueva obliga a descargar una miniatura fresca; la
  entrada antigua sale por eviction.
- **Disco** (`<cache>/cauce_media_thumbnails`, via `path_provider`):
  maximo 100 entradas / 16 MB, eviction LRU por ultimo acceso, indice
  `index.json` y escritura atomica (`.part` + rename). El listado
  puede paginar sin que el cache crezca sin control.
- **Memoria**: maximo 64 entradas / 8 MB de miniaturas ya
  re-escaladas (LRU). Nunca se sostiene el archivo original en
  memoria: son miniaturas (`ImageDescriptor` + codec con
  `targetWidth/targetHeight`, re-encodificadas como PNG).
- Las llamadas concurrentes de la misma clave se deduplican (una sola
  descarga). Cualquier fallo (red, decodificacion, disco) devuelve
  null y la tarjeta cae al lienzo de tipo sin bloquear el listado.

### Subida (pulido de lo existente)

- **Validacion previa al POST** (`MediaService.validateUploadFile`),
  espejo de las reglas del backend: extensiones permitidas (image:
  png/jpg/jpeg/gif/webp; video: mp4/webm/ogg/mov/mkv) y maximo 200 MB
  (`CAUCE_MEDIA_MAX_SIZE_MB` por defecto). Un archivo rechazado no
  gasta la LAN: se notifica antes de enviar nada.
- **Progreso real**: `onProgress` en el multipart (`ApiClient`
  envuelve el stream del cuerpo con un contador de bytes); barra
  determinista con porcentaje y boton deshabilitado mientras sube
  (sin dobles POST).
- **Errores especificos** via `ApiException`: `413` demasiado
  grande, `400/422` tipo o extension no valida (se conserva el
  `detail` del backend), `403` sin `content.manage` (MEDIADOR es solo
  lectura), `404` y perdida de conexion.

## Arquitectura

```
lib/
├── main.dart            punto de entrada, inyeccion de dependencias
├── app.dart             rutas nombradas + SessionGate (guard de sesion)
├── core/
│   ├── config/          ApiConfig (baseUrl via --dart-define)
│   ├── theme/           paleta y tema Cauce (design.md)
│   ├── network/         ApiClient + ApiException (red/auth/servidor)
│   └── utils/           JWT, fechas locales de la biblioteca
├── models/              User / Device / Media (esquemas del backend)
├── services/            AuthService, UserService, DeviceService,
│                        MediaService, ThumbnailService (miniaturas)
├── controllers/         DevicesController, MediaLibraryController
├── session/             TokenStorage (seguro) + SessionController
├── navigation/          MainShell (barra de 5 pestañas)
├── screens/             pantallas (media: biblioteca, detalle, registro)
├── widgets/             encabezados, badge LAN, fondos organicos
└── data/                demo_data.dart — valores estaticos provisionales
```

## Ejecutar

```bash
flutter pub get
flutter analyze
flutter test
```

En un telefono Android dentro de la LAN de la sala:

```bash
flutter run --release \
  --dart-define=CAUCE_SERVER_LOCAL_URL=http://10.15.1.150:8000
```

La URL por defecto ya apunta a `http://10.15.1.150:8000` (raiz del
backend, **sin** `/api`; la app lo anade). Se sobrescribe con
`--dart-define=CAUCE_SERVER_LOCAL_URL=...` si el servidor cambia de
IP. Para operar por fuera de la sala se configura
`--dart-define=CAUCE_SERVER_TAILSCALE_URL=http://100.x.y.z:8000`:
`ApiConfig.activeServerUrl` elige Tailscale si esta definida, local en
caso contrario, y tanto el badge LAN como toda la API usan esa URL. El
badge muestra la URL activa en un tooltip y el sondeo deja la direccion
y el motivo de cada fallo en el log (`flutter logs` / `adb logcat`).

> Android exige `INTERNET` y trafico HTTP en claro; ambos estan
> configurados (`AndroidManifest.xml` +
> `res/xml/network_security_config.xml`, que permite cleartext en
> general porque la app solo opera dentro de la LAN de la sala).

## Contratos del backend usados (verificados en el codigo)

| Operacion | Contrato | Estado |
|---|---|---|
| Login | `POST /api/auth/login` → `{access_token, token_type}` | implementado |
| Usuario actual | **no existe `/users/me`** | id obtenido del `sub` del JWT |
| Detalle de usuario | `GET /api/users/{id}` (permiso `users.view`) | solo ADMINISTRADOR |
| Edicion de usuario | `PATCH /api/users/{id}` (permiso de gestion del rol) | solo ADMINISTRADOR |
| Logout | **no existe endpoint** | borrado local del token |
| Listar medios | `GET /api/media?limit=&offset=` (`content.view`) | implementado (paginado) |
| Detalle de medio | `GET /api/media/{id}` (`content.view`) | implementado |
| Binario de medio | `GET /api/media/{id}/file` (`content.view`) | miniaturas/vista previa (solo imagenes) |
| Subir archivo | `POST /api/media` multipart (`content.manage`) | implementado (validacion + progreso) |
| Registrar URL | `POST /api/media/urls` JSON (`content.manage`) | implementado |
| Eliminar medio | `DELETE /api/media/{id}` 204 (`content.manage`) | implementado |
| Dispositivos / actividades | existen rutas pero fase 1 es solo visual | sin integracion |

No se inventan endpoints: no hay miniaturas de video (el backend no
las genera), ni conteo total del servidor (los chips de filtro cuentan
solo lo cargado en memoria), ni reproduccion.

## Limitaciones documentadas (biblioteca de medios)

1. **MEDIADOR = solo lectura.** Con `content.view` puede listar, ver
   detalle y previsualizar; los botones de subir/borrar solo aparecen
   con `content.manage` (ADMINISTRADOR) y un `403` del backend se
   informa con mensaje claro.
2. **Sin miniaturas de video.** El backend no genera miniaturas de
   video (no existe el endpoint) y la app **no descarga el video para
   fabricarlas**: la tarjeta muestra el lienzo con el icono de tipo y
   "Miniatura no disponible". Limitacion documentada, no dato
   fingido. El detalle de video muestra solo su metadata completa;
   aqui no se reproduce.
3. **URLs = recursos externos.** Lienzo con icono de enlace y la
   direccion copiable en el detalle; el backend nunca las descarga.
4. **Sin descarga ni reproduccion en la app movil.** La vista previa
   es solo de imagenes, en memoria y re-escalada.
5. **Recuento de filtros local.** Los chips cuentan los medios ya
   cargados en memoria (paginados), no un total del servidor (no hay
   endpoint de conteo).

## Limitaciones documentadas (fase 1)

1. **Perfil de MEDIADOR de solo lectura.** El backend no expone
   `/users/me` y el rol MEDIADOR no tiene `users.view`: la app muestra
   el correo del login y decodifica el `sub`/`exp` del JWT. El rol
   mostrado se infiere del resultado (403 → mediador); es la unica
   inferencia realizada.
2. **Edicion solo para ADMINISTRADOR.** Un admin puede actualizar
   nombre, correo y PIN via `PATCH /api/users/{id}` (posee
   `users.admins.manage`). El mediador recibe 403 y la UI lo informa.
3. **Logout local.** Al no existir endpoint de cierre de sesion, se
   elimina el token almacenado; el token sigue valido hasta su
   expiracion (8 h) si alguien mas lo hubiera capturado.
4. **Pantallas base sin logica.** Inicio y Actividades usan
   `lib/data/demo_data.dart` (contenido provisional); quedan fuera de
   esta fase. Ninguna vista de medios depende de `demo_data`.
5. **Iconos de estacion.** El mapeo `icono 1..6.png` asume el orden del
   manual de marca (VR, Repositorio, Tactil, Audio, AR, Totem);
   confirmar visualmente en el dispositivo.
6. **Quick switcher del login.** El prototipo Stitch incluia botones
   "Rapido: Mediador / Admin" con credenciales fijas; se omiten por
   seguridad (sin credenciales hardcodeadas).

## Seguridad

- El token se guarda en `flutter_secure_storage`; nunca en
  `SharedPreferences` ni en logs.
- No se persiste el PIN; el "recordar correo" guarda solo el email.
- Errores clasificados: conexion (sin ruta al servidor),
  autenticacion (401/403) y respuesta del servidor (4xx/5xx con
  `{code, detail}`).

## Dependencias y su justificacion

| Paquete | Por que |
|---|---|
| `http` | Cliente HTTP contra el backend FastAPI de la LAN. |
| `file_picker` | Seleccion de archivos locales para la subida de medios (RF-008 fase 1). |
| `flutter_secure_storage` | Token JWT en almacenamiento seguro del dispositivo. |
| `provider` | Estado de sesion/biblioteca y notificacion a las pantallas. |
| `path_provider` | Directorio de cache del sistema para las miniaturas de la biblioteca (`getTemporaryDirectory`); imprescindible para el cache de disco con limite. |

Sin librerias de estado nuevas: la biblioteca sigue con
`ChangeNotifier` + `provider`.
