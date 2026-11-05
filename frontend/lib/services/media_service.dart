/// Servicio de medios contra el backend Cauce (RF-008 fase 1).
///
/// Contratos reales:
/// - GET    /api/media                (permiso `content.view`)
/// - GET    /api/media/{id}           (permiso `content.view`)
/// - GET    /api/media/{id}/file      (permiso `content.view`; binario)
/// - POST   /api/media                multipart (permiso `content.manage`)
/// - POST   /api/media/urls           JSON     (permiso `content.manage`)
/// - DELETE /api/media/{id}           204      (permiso `content.manage`)
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../models/media.dart';

class MediaService {
  MediaService({required ApiClient client}) : _client = client;

  final ApiClient _client;

  /// Limite de tamano de subida del backend
  /// (`CAUCE_MEDIA_MAX_SIZE_MB`, 200 por defecto). Se valida en la UI
  /// antes de gastar la LAN.
  static const int maxUploadBytes = 200 * 1024 * 1024;

  /// Extensiones permitidas por tipo (espejo de la validacion del
  /// backend: el servidor sigue siendo la autoridad).
  static const List<String> imageExtensions = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
  ];
  static const List<String> videoExtensions = [
    'mp4',
    'webm',
    'ogg',
    'mov',
    'mkv',
  ];
  static const List<String> pdfExtensions = ['pdf'];
  static const List<String> allowedExtensions = [
    ...imageExtensions,
    ...videoExtensions,
    ...pdfExtensions,
  ];

  /// Tipo de medio ('image' | 'video' | 'pdf') segun la extension del
  /// nombre de archivo; null si la extension no esta permitida.
  static String? mediaTypeForExtension(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (imageExtensions.contains(ext)) return 'image';
    if (videoExtensions.contains(ext)) return 'video';
    if (pdfExtensions.contains(ext)) return 'pdf';
    return null;
  }

  /// Validacion previa al envio (antes del POST). Devuelve el mensaje
  /// de error para la UI o null cuando el archivo puede subir.
  static String? validateUploadFile(String fileName, int fileSizeBytes) {
    if (fileName.isEmpty) {
      return 'Selecciona un archivo antes de guardar.';
    }
    if (mediaTypeForExtension(fileName) == null) {
      return 'La extension de "$fileName" no es valida. Permite: '
          '${allowedExtensions.join(', ')}.';
    }
    if (fileSizeBytes > maxUploadBytes) {
      final readable = _readableSize(fileSizeBytes);
      return 'El archivo pesa $readable y supera el limite de '
          '${_readableSize(maxUploadBytes)}: la subida se rechazo antes de '
          'enviarlo al servidor.';
    }
    return null;
  }

  static String _readableSize(int bytes) {
    const mb = 1024 * 1024;
    if (bytes < 1024) return '$bytes B';
    if (bytes < mb) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  /// Lista de medios (orden: mas recientes primero).
  Future<List<Media>> listMedia({int limit = 50, int offset = 0}) async {
    final data = await _client.get(
      ApiConfig.mediaPath,
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return (data as List<dynamic>)
        .map((item) => Media.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Detalle de un medio por id.
  Future<Media> getMedia(int id) async {
    final data = await _client.get('${ApiConfig.mediaPath}/$id');
    return Media.fromJson(data as Map<String, dynamic>);
  }

  /// Binario almacenado de un medio (vistas previas). Requiere el
  /// header Authorization, por eso baja por ApiClient en lugar de
  /// Image.network.
  Future<Uint8List> getMediaFileBytes(Media media) async {
    return _client.getBytes('${ApiConfig.mediaPath}/${media.id}/file');
  }

  /// Sube un archivo (image | video) como multipart/form-data.
  ///
  /// El `filename` original viaja en la parte `file`; el nombre en
  /// [name] es solo display (opcional, el servidor conserva el
  /// original si llega vacio). [onProgress] reporta el avance del
  /// envio por la LAN (bytes enviados, total).
  Future<Media> uploadFile({
    required Uint8List bytes,
    required String filename,
    required String mediaType,
    String? name,
    void Function(int sent, int total)? onProgress,
  }) async {
    final data = await _client.postMultipart(
      ApiConfig.mediaPath,
      fields: {
        'media_type': mediaType,
        if (name != null && name.isNotEmpty) 'name': name,
      },
      files: [http.MultipartFile.fromBytes('file', bytes, filename: filename)],
      onProgress: onProgress,
    );
    return Media.fromJson(data as Map<String, dynamic>);
  }

  /// Registra una URL externa (http/https). El backend nunca la
  /// descarga: solo guarda sus metadatos.
  Future<Media> registerUrl({
    required String name,
    required String url,
    String? mimeType,
  }) async {
    final data = await _client.post(
      '${ApiConfig.mediaPath}/urls',
      body: {
        'name': name,
        'url': url,
        if (mimeType != null && mimeType.isNotEmpty) 'mime_type': mimeType,
      },
    );
    return Media.fromJson(data as Map<String, dynamic>);
  }

  /// Elimina un medio (metadatos y archivo asociado). 204.
  Future<void> deleteMedia(int id) async {
    await _client.delete('${ApiConfig.mediaPath}/$id');
  }
}
