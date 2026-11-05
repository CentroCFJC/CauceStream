# CAUCE Stream - Plan de Desarrollo

## Fase 1: Configuracion del Entorno ✓

- [x] Instalar Flutter SDK (v3.27.4)
- [x] Crear proyecto Flutter `cauce_stream` con soporte Android
- [x] Configurar AndroidManifest.xml para Android TV (leanback, banner)
- [x] Configurar build.gradle (minSdk 24)
- [x] Agregar dependencias (http, video_player, cached_network_image, path_provider)

## Fase 2: Modelos de Datos ✓

- [x] `VideoItem` - id, name, videoUrl, thumbnailUrl, duration
- [x] `Category` - id, name, list de VideoItem

## Fase 3: Servicio de Google Drive ✓

- [x] `GoogleDriveService` - fetchCatalog()
- [x] Listar carpetas (canales) desde Drive API v3
- [x] Listar videos .mp4 dentro de cada carpeta
- [x] Resolver miniaturas (Prioridad 1: JPG同名, Prioridad 2: thumbnailLink, Prioridad 3: placeholder)
- [x] Construir URLs de descarga directa

## Fase 4: Pantalla Principal (Home) ✓

- [x] Logo CAUCE Stream institucional
- [x] Lista vertical de canales
- [x] Carruseles horizontales de videos por canal
- [x] Navegacion por foco con control remoto
- [x] Estados de carga y error

## Fase 5: Pantalla de Detalle ✓

- [x] Miniatura del video
- [x] Nombre del video
- [x] Duracion
- [x] Boton "Reproducir"

## Fase 6: Display de Video ✓

- [x] Pantalla completa
- [x] VideoPlayerController con networkUrl
- [x] Controles basicos (play/pause, progress bar)
- [x] Regreso automatico al finalizar

## Fase 7: Proximos Pasos / Mejoras Futuras

- [ ] Configurar Google Drive API Key real en `lib/config/constants.dart`
- [ ] Configurar el ID de la carpeta raiz de Drive
- [ ] Agregar icono/banner personalizado de CAUCE
- [x] Agregar splash screen
- [ ] Implementar actualizacion automatica periodica del catalogo
- [ ] Agregar animaciones de transicion entre pantallas
- [ ] Probar en dispositivo Android TV real
- [ ] Optimizar rendimiento con listas perezosas
- [ ] Manejar errores de red mas robustamente

## Fase 8: Fix Decoder Amlogic (TCL Google TV) ✓

- [x] Identificar causa raiz: `OMX.amlogic.avc.decoder.awesome2` falla con formato 1080x1080
- [x] Implementar `MediaCodecSelector` personalizado que excluye decoder Amlogic problematico
- [x] Habilitar `setEnableDecoderFallback(true)` en `DefaultRenderersFactory`
- [x] Mantener `forceDisableAsynchronous()` para evitar crash secundario en `MediaCodec.stop()`
- [x] Aplicar fix en `TextureVideoPlayer.java` y `PlatformViewVideoPlayer.java`
- [x] Mejorar URL de descarga de Google Drive (API v3 con `alt=media` evita redireccion >25MB)
- [x] Agregar logging detallado en `player_screen.dart` para depuracion
- [x] Mejorar mensajes de error al usuario

## Arquitectura

```
lib/
├── main.dart                    # Punto de entrada
├── config/
│   └── constants.dart           # Configuracion (API Key, Folder ID)
├── models/
│   ├── category.dart            # Modelo Category
│   └── video_item.dart          # Modelo VideoItem
├── services/
│   └── google_drive_service.dart # Llamadas a Google Drive API
├── screens/
│   ├── splash_screen.dart       # Pantalla de carga
│   ├── home_screen.dart         # Pantalla principal (contenido)
│   ├── detail_screen.dart       # Pantalla de detalle del video
│   └── player_screen.dart       # Display de video
└── widgets/
    ├── category_row.dart        # Fila de canal con carrusel
    └── video_card.dart          # Tarjeta de video individual
```

## Configuracion Requerida

Antes de ejecutar, editar `lib/config/constants.dart`:

| Constante | Descripcion |
|-----------|-------------|
| `driveApiKey` | API Key de Google Cloud con Drive API habilitada |
| `driveFolderId` | ID de la carpeta raiz de Google Drive |

## Comandos

```bash
# Desarrollo
flutter run

# Build APK
flutter build apk --release

# Analisis
flutter analyze
```
