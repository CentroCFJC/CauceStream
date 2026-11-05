import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/playback_message.dart';

/// Descarga autenticada de medios del servidor Cauce (única vía de
/// acceso a `/api/media/{id}/file` con el header `X-Device-Key`).
///
/// Patrón del screensaver: descarga a un archivo temporal + rename
/// atómico, para no dejar jamás una copia parcial en la caché. Sin
/// reintentos en cascada: si falla, el servicio de playback reporta
/// `playback.error` y espera la próxima orden del administrador.
class CauceMediaDownloader {
  CauceMediaDownloader({
    String? deviceKey,
    http.Client? client,
    this.timeout = const Duration(minutes: 5),
  })  : _deviceKey = deviceKey,
        _client = client ?? http.Client();

  final String? _deviceKey;
  final http.Client _client;

  /// Timeout generoso: archivos grandes por LAN. Cubre la descarga
  /// completa (streaming), no la conexión sola.
  final Duration timeout;

  /// Resuelve la URL absoluta de un `file_url` RELATIVO del contrato
  /// (p. ej. `/api/media/5/file`) anteponiendo la base de la API. Por
  /// concatenación de strings: `file_url` ya viene URL-encoded del
  /// backend y no debe re-codificarse.
  static Uri resolveUri(String baseUrl, String relativeFileUrl) {
    final base = Uri.parse(baseUrl);
    final port = base.hasPort ? ':${base.port}' : '';
    final origin = '${base.scheme}://${base.host}$port';
    final path = relativeFileUrl.startsWith('/')
        ? relativeFileUrl
        : '/$relativeFileUrl';
    return Uri.parse('$origin$path');
  }

  /// Archivo de caché estable para un medio (uno por media_id).
  static File cacheFileFor(Directory cacheDir, AssignmentMedia media) {
    final safeName = media.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('${cacheDir.path}/cauce_media_$safeName');
  }

  /// Devuelve el archivo cacheado si existe y es VÁLIDO (no vacío y,
  /// cuando el contrato informa `file_size`, de ese tamaño exacto);
  /// en caso contrario lo descarga con `X-Device-Key`.
  ///
  /// Un medio ya disponible y validado jamás se vuelve a descargar.
  Future<File> ensureDownloaded({
    required String baseUrl,
    required AssignmentMedia media,
    required File destination,
  }) async {
    if (await _isValidCache(destination, media)) {
      return destination;
    }

    final fileUrl = media.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      throw const MediaDownloadException('file_url ausente en el contrato');
    }

    final uri = resolveUri(baseUrl, fileUrl);
    await download(uri, destination);
    return destination;
  }

  /// Descarga a `destination` (temporal + rename atómico). Lanza
  /// [MediaDownloadException] ante fallo de red o estado no 2xx.
  Future<void> download(Uri uri, File destination) async {
    final request = http.Request('GET', uri);
    final key = _deviceKey;
    if (key != null) {
      request.headers['X-Device-Key'] = key;
    }

    try {
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Drena la respuesta para liberar la conexión antes de fallar.
        try {
          await response.stream.drain();
        } catch (_) {}
        throw MediaDownloadException(
          'descarga fallida: HTTP ${response.statusCode} '
          '${response.reasonPhrase ?? ''} en $uri',
        );
      }

      final tempFile = File('${destination.path}.tmp');
      try {
        await response.stream.pipe(tempFile.openWrite()).timeout(timeout);
        if (await destination.exists()) {
          await destination.delete();
        }
        await tempFile.rename(destination.path);
      } catch (e) {
        if (await tempFile.exists()) {
          await tempFile.delete().catchError((_) => tempFile);
        }
        rethrow;
      }
    } on MediaDownloadException {
      rethrow;
    } on TimeoutException {
      throw MediaDownloadException('timeout descargando $uri');
    } catch (e) {
      throw MediaDownloadException('error descargando $uri: $e');
    }
  }

  Future<bool> _isValidCache(File file, AssignmentMedia media) async {
    try {
      if (!await file.exists()) return false;
      final size = await file.length();
      if (size == 0) return false;
      final expected = media.fileSize;
      if (expected != null && expected > 0 && size != expected) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Fallo de descarga de un medio. El mensaje nunca contiene el secreto
/// del dispositivo.
class MediaDownloadException implements Exception {
  const MediaDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
