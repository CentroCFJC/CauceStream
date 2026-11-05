import 'dart:convert';
import 'dart:io';

import 'package:cauce_stream/models/playback_message.dart';
import 'package:cauce_stream/services/cauce_media_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AssignmentMedia imageMedia({
  String fileUrl = '/api/media/5/file',
  int? fileSize = 20480,
}) {
  final parsed = AssignmentMedia.fromJson({
    'name': 'portada.png',
    'media_type': 'image',
    'mime_type': 'image/png',
    'file_size': fileSize,
    'file_url': fileUrl,
    'external_url': null,
  });
  expect(parsed, isNotNull);
  return parsed!;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cauce_media_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('resolveUri antepone la base de la API al file_url relativo',
      () async {
    final uri = CauceMediaDownloader.resolveUri(
      'http://10.15.1.150:8000',
      '/api/media/5/file',
    );
    expect(
      uri.toString(),
      'http://10.15.1.150:8000/api/media/5/file',
    );
  });

  test('descarga con X-Device-Key y escribe el archivo completo',
      () async {
    Uri? capturedUri;
    String? capturedKey;
    final payload = List<int>.generate(20480, (i) => i % 251);
    final client = MockClient((request) async {
      capturedUri = request.url;
      capturedKey = request.headers['X-Device-Key'];
      return http.Response.bytes(payload, 200);
    });
    final downloader = CauceMediaDownloader(
      deviceKey: 'secreto-compartido',
      client: client,
    );
    final destination = File('${tempDir.path}/media_5.png');

    await downloader.download(
      CauceMediaDownloader.resolveUri('http://10.15.1.150:8000', '/api/media/5/file'),
      destination,
    );

    expect(capturedKey, 'secreto-compartido');
    expect(
      capturedUri.toString(),
      'http://10.15.1.150:8000/api/media/5/file',
    );
    expect(await destination.exists(), isTrue);
    expect(await destination.length(), payload.length);
    expect(await destination.readAsBytes(), payload);
    // No queda archivo temporal.
    expect(await File('${destination.path}.tmp').exists(), isFalse);
    downloader.dispose();
  });

  test('sin deviceKey no se envía el header (modo transición)', () async {
    String? capturedKey;
    final client = MockClient((request) async {
      capturedKey = request.headers['X-Device-Key'];
      return http.Response.bytes([1, 2, 3], 200);
    });
    final downloader = CauceMediaDownloader(client: client);
    await downloader.download(
      Uri.parse('http://server:8000/api/media/1/file'),
      File('${tempDir.path}/a.bin'),
    );
    expect(capturedKey, isNull);
    downloader.dispose();
  });

  test('HTTP de error lanza sin dejar archivo ni temporal', () async {
    final client = MockClient(
      (request) async => http.Response('forbidden', 403),
    );
    final downloader = CauceMediaDownloader(
      deviceKey: 'k',
      client: client,
    );
    final destination = File('${tempDir.path}/media_5.png');

    await expectLater(
      downloader.download(
        Uri.parse('http://server:8000/api/media/5/file'),
        destination,
      ),
      throwsA(isA<MediaDownloadException>()),
    );
    expect(await destination.exists(), isFalse);
    expect(await File('${destination.path}.tmp').exists(), isFalse);
    downloader.dispose();
  });

  group('ensureDownloaded (caché)', () {
    test('reutiliza la copia válida sin descargar de nuevo', () async {
      var downloads = 0;
      final client = MockClient((request) async {
        downloads++;
        return http.Response.bytes(utf8.encode('contenido'), 200);
      });
      final downloader = CauceMediaDownloader(client: client);
      final media = imageMedia(fileSize: null); // tamaño desconocido
      final destination = CauceMediaDownloader.cacheFileFor(tempDir, media);
      await destination.writeAsBytes(utf8.encode('contenido'));

      final file = await downloader.ensureDownloaded(
        baseUrl: 'http://server:8000',
        media: media,
        destination: destination,
      );

      expect(file.path, destination.path);
      expect(downloads, 0, reason: 'la caché válida no se re-descarga');
      downloader.dispose();
    });

    test('descarga cuando falta el archivo o el tamaño no coincide',
        () async {
      var downloads = 0;
      final client = MockClient((request) async {
        downloads++;
        return http.Response.bytes(utf8.encode('contenido nuevo'), 200);
      });
      final downloader = CauceMediaDownloader(client: client);
      final media = imageMedia(fileSize: 16);
      final destination = CauceMediaDownloader.cacheFileFor(tempDir, media);

      // Sin archivo en caché.
      var file = await downloader.ensureDownloaded(
        baseUrl: 'http://server:8000',
        media: media,
        destination: destination,
      );
      expect(downloads, 1);
      expect(utf8.decode(await file.readAsBytes()), 'contenido nuevo');

      // Con tamaño incorrecto (caché corrupta) se re-descarga.
      await destination.writeAsString('corto');
      file = await downloader.ensureDownloaded(
        baseUrl: 'http://server:8000',
        media: media,
        destination: destination,
      );
      expect(downloads, 2);
      expect(utf8.decode(await file.readAsBytes()), 'contenido nuevo');
      downloader.dispose();
    });
  });
}
