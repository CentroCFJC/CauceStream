# CAUCE Stream

Sistema de distribucion de contenido para la Sala CAUCE del **Centro de Ciencias Francisco Jose de Caldas**.

Explora y reproduce videos educativos organizados por canales, con contenido administrado mediante una carpeta publica de Google Drive.

## Requisitos

- Flutter SDK ^3.6.2
- Android TV (API 24+) como dispositivo objetivo

## Configuracion

1. Clona el repositorio y entra en la carpeta:
   ```sh
   git clone <repo-url>
   cd cauce_stream
   ```

2. Copia el archivo de entorno:
   ```sh
   cp .env.example .env
   ```

3. Edita `.env` con tus credenciales de Google Drive y el servidor Cauce:
   ```env
   DRIVE_API_KEY=tu-api-key-de-google-drive
   DRIVE_FOLDER_ID=id-de-la-carpeta-raiz-en-drive
   CAUCE_SERVER_URL=http://ip-del-servidor-cauce:8000
   ```

   > `CAUCE_SERVER_URL` es opcional: habilita el heartbeat periodico hacia el servidor Cauce (reporte de estado del dispositivo). Sin ella, la aplicacion funciona igual, sin heartbeat. El `device_uid` no se configura: es el nombre del dispositivo tal como lo expone el sistema operativo.

   > **Importante:** El archivo `.env` contiene credenciales sensibles y esta incluido en `.gitignore`.

4. Instala las dependencias:
   ```sh
   flutter pub get
   ```

5. Ejecuta la aplicacion:
   ```sh
   flutter run           # desarrollo
   flutter run -d emulator-5554  # en emulador Android TV
   flutter build apk --release   # APK de produccion
   ```

## Estructura del contenido en Google Drive

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

Cada subcarpeta es un canal. Los archivos `.mp4` son los videos. Las imagenes `.jpg`/`.png` con el mismo nombre del video se usan como miniaturas (prioridad 1); si no existen, se usa la miniatura generada automaticamente por Google Drive.

## Funcionalidades

### Navegacion por control remoto
Toda la interfaz es navegable con las flechas del control remoto Android TV (arriba/abajo/izquierda/derecha), Enter para seleccionar y Back para retroceder. No requiere interaccion tactil.

### Pantalla principal
- **Logo de CAUCE** en la esquina superior izquierda y logo institucional en la derecha.
- **Banner hero**: al seleccionar un video, se muestra un banner con el titulo, boton "Reproducir" y "Mas informacion", con navegacion por foco entre los botones.
- **Canales en carrusel horizontal**: cada canal despliega sus videos en una fila horizontal con scroll. Al hacer foco en un video, el carrusel se centra automaticamente.
- **Paneles de gradiente**: bordes oscuros en los extremos del carrusel para indicar contenido desplazable.
- **Panel de informacion**: al presionar el boton circular se despliega un panel informativo de la Sala CAUCE.

### Video cards
Cada video se muestra como una tarjeta con miniatura y nombre. Al recibir foco:
- Borde blanco brillante y sombra.
- Si el nombre es mas largo que el contenedor, se activa un efecto **marquee** (desplazamiento horizontal del texto).

### Display de video
- Reproduccion en pantalla completa usando ExoPlayer (Android TV).
- Barra de control inferior: boton play/pausa, indicador de progreso (seeking permitido), tiempo transcurrido y duracion total.
- Al finalizar el video, regresa automaticamente al contenido despues de 500 ms.
- En Windows, muestra un mensaje informativo con boton para abrir el video en el navegador.

### Sincronizacion con Google Drive
Al iniciar la aplicacion:
1. Consulta la carpeta raiz en Google Drive.
2. Lee las subcarpetas (canales), ordenadas por fecha de modificacion descendente.
3. Dentro de cada carpeta, lista los archivos `.mp4`.
4. Resuelve las miniaturas (imagen del mismo nombre > miniatura automatica de Drive > icono generico).
5. Construye el catalogo en memoria.

## Arquitectura

```
lib/
├── main.dart                          # Entry point
├── config/
│   └── constants.dart                 # AppConfig (API Key, Folder ID)
├── models/
│   ├── category.dart                  # Modelo Category
│   └── video_item.dart                # Modelo VideoItem
├── screens/
│   ├── splash_screen.dart             # Pantalla de carga
│   ├── home_screen.dart               # Pantalla principal con catalogo
│   └── player_screen.dart             # Display de video
├── services/
│   └── google_drive_service.dart      # Cliente Google Drive API v3
└── widgets/
    ├── category_row.dart              # Fila horizontal de canal
    └── video_card.dart                # Tarjeta de video con foco y marquee
```

## Stack tecnico

| Componente | Tecnologia |
|---|---|
| **Framework** | Flutter (Dart SDK ^3.6.2) |
| **Plataforma destino** | Android TV (API 24+) |
| **Fuente de contenido** | Google Drive API v3 (publica, sin OAuth) |
| **Display** | `video_player` (ExoPlayer en Android) |
| **Miniaturas** | `cached_network_image` (con cache local) |
| **Env vars** | `flutter_dotenv` |
| **API HTTP** | `http` |
| **Fallback desktop** | `url_launcher` |
| **Navegacion** | Nativa con `Focus` + `FocusNode` + `LogicalKeyboardKey` |
| **Estado** | `StatefulWidget` con `setState` (sin libreria externa) |

## Comandos utiles

```sh
flutter analyze          # Analisis estatico
flutter test             # Pruebas unitarias
flutter build apk --release  # Build release para Android TV
```

## Desarrollo

Este proyecto usa `flutter_lints` para mantener la calidad del codigo. Corre `flutter analyze` antes de cada commit para asegurar que no haya warnings ni errores.

## Licencia

Uso interno — Centro de Ciencias Francisco Jose de Caldas.
