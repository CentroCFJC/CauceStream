import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();

  static const String appName = 'CAUCE Stream';

  static String get driveApiKey => _get('DRIVE_API_KEY');
  static String get driveFolderId => _get('DRIVE_FOLDER_ID');

  /// URL base del servidor Cauce en la LAN (p. ej. http://10.15.1.150:8000).
  /// Opcional: si no está definida, la app funciona igual, solo que sin
  /// heartbeats (a diferencia de las claves de Drive, no lanza).
  static String? get cauceServerUrl {
    final value = dotenv.env['CAUCE_SERVER_URL'];
    if (value == null || value.trim().isEmpty) return null;
    // Normaliza solo el formato de la URL, nunca su contenido.
    return value.trim().replaceAll(RegExp(r'/+$'), '');
  }

  /// Secreto compartido con el servidor Cauce (header X-Device-Key en
  /// el heartbeat y el WebSocket). Opcional: si no está definida en el
  /// servidor, no se envía (modo transición).
  static String? get deviceSecret {
    final value = dotenv.env['CAUCE_DEVICE_SECRET'];
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  static const String driveBaseUrl = 'https://www.googleapis.com/drive/v3';
  static const String driveDownloadUrl = 'https://www.googleapis.com/drive/v3/files';

  /// Carpeta de Google Drive que contiene el video a reproducir en bucle.
  /// https://drive.google.com/drive/folders/1Xc6MkEqWfifBb17MSHLuGe6Dou1FlYx_
  static const String playbackFolderId = '1Xc6MkEqWfifBb17MSHLuGe6Dou1FlYx_';

  static String _get(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw Exception('$key no está definida en el archivo .env');
    }
    return value;
  }
}
