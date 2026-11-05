# CAUCE Stream — Especificacion Tecnica y Funcional

## Vision

CAUCE Stream es el sistema de distribucion de contenido para la Sala CAUCE del Centro de Ciencias Francisco Jose de Caldas. Es una aplicacion para Android TV que permite explorar y reproducir contenido educativo organizado por canales, con administracion remota mediante Google Drive.

## Objetivo

Proveer una plataforma institucional confiable que permita al personal del centro de ciencias:
- Administrar el contenido de forma remota desde Google Drive.
- Reproducir videos educativos en las pantallas de la Sala CAUCE.
- Navegar el contenido con control remoto Android TV sin necesidad de interaccion tactil.

## Usuarios

- **Administradores**: personal del Centro de Ciencias, gestiona el contenido desde Google Drive.
- **Visitantes**: personal de la Sala CAUCE, navega y reproduce el contenido con el control remoto.

## Flujo de la aplicacion

1. **Pantalla de carga**: Al iniciar, se muestra el logo de CAUCE, titulo "CAUCE Stream" y subtitulo "Sistema de distribucion de contenido" con un indicador de carga elegante.
2. **Pantalla principal**: Catalogo de videos organizado por canales en carruseles horizontales.
3. **Display**: Reproduccion a pantalla completa del video seleccionado.

## Interfaz

### Pantalla de carga
- Logo institucional de CAUCE.
- Titulo: CAUCE Stream.
- Subtitulo: Sistema de distribucion de contenido.
- Indicador de carga lineal animado.

### Pantalla principal
1. **Barra superior**: logo de CAUCE (izquierda), logo institucional (derecha), boton de informacion.
2. **Banner hero**: al seleccionar un video desde los carruseles, se muestra banner con titulo y botones "Reproducir" y "Mas informacion".
3. **Canales**: cada canal es una fila horizontal con scroll de videos.
4. **Panel de informacion**: desplegable con datos de la Sala CAUCE.

### Display
- Pantalla completa con video.
- Controles inferiores: play/pausa, barra de progreso con seeking, tiempos.
- Ocultacion automatica de controles.
- Regreso automatico al finalizar.

## Navegacion

Toda la navegacion se realiza mediante el control remoto Android TV (D-pad):
- **Arriba/Abajo**: cambiar entre canales.
- **Izquierda/Derecha**: desplazarse entre videos dentro de un canal.
- **Enter/Select**: seleccionar video o accion.
- **Back/Escape**: retroceder.

## Configuracion

La aplicacion requiere dos variables de entorno en `.env`:
- `DRIVE_API_KEY`: API Key de Google Cloud con Drive API v3 habilitada.
- `DRIVE_FOLDER_ID`: ID de la carpeta raiz en Google Drive que contiene los canales.
- `CAUCE_SERVER_URL` (opcional): URL base del servidor Cauce en la LAN (p. ej. `http://10.15.1.150:8000`). Habilita el heartbeat periodico hacia el servidor (reporte de estado del dispositivo). Si no esta definida, la aplicacion funciona igual, sin heartbeat. El `device_uid` no se configura: es el nombre del dispositivo tal como lo expone el sistema operativo.

## Estructura de contenido en Google Drive

```
Carpeta raiz (DRIVE_FOLDER_ID)
├── Astronomia/
│   ├── Agujeros Negros.mp4
│   └── Agujeros Negros.jpg      (miniatura opcional)
├── Robotica/
│   ├── Introduccion a Arduino.mp4
│   └── Arduino.jpg              (miniatura opcional)
└── ...
```

- **Carpetas**: cada subcarpeta es un canal.
- **Videos**: archivos `.mp4` dentro de cada canal.
- **Miniaturas**: imagenes `.jpg`/`.png` con el mismo nombre del video (prioridad 1). Si no existen, se usa la miniatura generada automaticamente por Google Drive (prioridad 2) o un placeholder generico (prioridad 3).

## Stack tecnico

| Capa | Tecnologia |
|------|-----------|
| Framework | Flutter (Dart SDK ^3.6.2) |
| Plataforma | Android TV (API 24+) |
| Lenguaje | Dart |
| Reproduccion | video_player (ExoPlayer) |
| API Backend | Google Drive API v3 |
| HTTP | package:http |
| Imagenes | cached_network_image |
| Variables de entorno | flutter_dotenv |
| Navegacion | Focus + FocusNode nativos |

## Patron de arquitectura

La aplicacion sigue un patron simple sin libreria de estado externa:
- `StatefulWidget` con `setState` para estado local.
- `GoogleDriveService` como singleton para acceso a datos.
- Widgets reutilizables (`CategoryRow`, `VideoCard`) para la UI.

## Limitaciones conocidas

- **Solo Android TV**: el reproductor de video solo funciona en Android TV (ExoPlayer). En otras plataformas (Windows, web) se muestra un fallback con enlace al navegador.
- **Decoder Amlogic**: en dispositivos TCL Google TV, el decoder `OMX.amlogic.avc.decoder.awesome2` falla con videos de ciertas resoluciones. Se implemento un fix en el plugin `video_player_android` local para excluir ese decoder.
- **Sin autenticacion**: el contenido debe estar en una carpeta publica de Google Drive (acceso "Cualquier persona con el enlace").
- **Sin persistencia local**: el catalogo se carga desde Drive en cada inicio de la aplicacion. No hay base de datos local ni cache del catalogo.

## Assets

- **Logo CAUCE**: asset `assets/logo.png`.
- **Logo cuadrado**: asset `assets/logo_square.png` (usado para iconos de launcher).
- **Banner por defecto**: asset `assets/cabecera.png` (fondo del hero cuando no hay video seleccionado).
- **Logo CAUCE remoto**: cargado desde Cloudinary en la barra superior.
