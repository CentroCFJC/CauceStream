// Pruebas de la fase de data real del medio: caché de miniaturas de
// imagenes (disco LRU + memoria, invalidacion por updated_at), data
// real en la tarjeta del listado, validacion previa de la subida y
// progreso del envio multipart.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/media_library_controller.dart';
import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/models/media.dart';
import 'package:cauce_stream/screens/media/media_library_screen.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';

Map<String, dynamic> mediaJson({
  int id = 1,
  String name = 'Banner_Bienvenida.png',
  String mediaType = 'image',
  String? mimeType = 'image/png',
  int? fileSize = 8400,
  String? storageKey = 'images/banner.png',
  String? externalUrl,
  String updatedAt = '2026-10-19T14:00:00Z',
}) =>
    {
      'id': id,
      'name': name,
      'media_type': mediaType,
      'mime_type': mimeType,
      'file_size': fileSize,
      'storage_key': storageKey,
      'external_url': externalUrl,
      'created_at': '2026-10-19T14:00:00Z',
      'updated_at': updatedAt,
    };

/// PNG real generado con el engine (PictureRecorder): unico metodo
/// disponible en tests para producir bytes decodificables.
Future<Uint8List> pngBytes({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Dimensiones de una imagen ya decodificada.
Future<(int, int)> dimensionsOf(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = (frame.image.width, frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return size;
}

ApiClient _apiClient(http.Client client, {String? token}) => ApiClient(
      baseUrl: 'http://10.15.1.150:8000/api',
      client: client,
    )..accessToken = token;

Directory _thumbnailDir() =>
    Directory.systemTemp.createTempSync('cauce_thumbs_test');

/// Cliente mock que sirve el listado vacio y [png] para cualquier
/// `GET /api/media/{id}/file`, contando las descargas de binarios.
MockClient _fileClient(Uint8List png, {void Function(int downloads)? onDownload}) {
  var downloads = 0;
  return MockClient((request) async {
    if (RegExp(r'^/api/media/\d+/file$').hasMatch(request.url.path)) {
      downloads += 1;
      onDownload?.call(downloads);
      return http.Response.bytes(png, 200,
          headers: {'content-type': 'image/png'});
    }
    return http.Response('[]', 200,
        headers: {'content-type': 'application/json'});
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailService', () {
    test('genera la miniatura re-escalada y no vuelve a descargarla',
        () async {
      final original = await pngBytes(width: 640, height: 480);
      var downloads = 0;
      final client = _fileClient(original, onDownload: (d) => downloads = d);
      final service = MediaService(client: _apiClient(client, token: 'jwt'));
      final thumbs = ThumbnailService(
        service: service,
        cacheDirectory: _thumbnailDir(),
      );
      final media = Media.fromJson(mediaJson());

      final thumb1 = await thumbs.thumbnail(media);
      final thumb2 = await thumbs.thumbnail(media);

      expect(thumb1, isNotNull);
      expect(thumb2, same(thumb1)); // memoria: sin nueva decodificacion
      expect(downloads, 1); // una sola descarga del original

      // Re-escalada: la miniatura nunca sostiene el tamano original.
      final (w, h) = await dimensionsOf(thumb1!);
      expect(w, 400);
      expect(h, 300);
    });

    test('sirve desde disco en una nueva sesion, sin redescargar',
        () async {
      final original = await pngBytes(width: 320, height: 240);
      var downloads = 0;
      final client = _fileClient(original, onDownload: (d) => downloads = d);
      final dir = _thumbnailDir();

      final first = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: dir,
      );
      final media = Media.fromJson(mediaJson());
      final thumb = await first.thumbnail(media);
      expect(thumb, isNotNull);
      expect(downloads, 1);

      // Nueva instancia (app reiniciada): solo cache de disco.
      final second = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: dir,
      );
      final fromDisk = await second.thumbnail(media);
      expect(fromDisk, isNotNull);
      expect(downloads, 1);
    });

    test('invalida la clave cuando updated_at cambia', () async {
      final original = await pngBytes(width: 64, height: 64);
      var downloads = 0;
      final client = _fileClient(original, onDownload: (d) => downloads = d);
      final thumbs = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: _thumbnailDir(),
      );

      final v1 = Media.fromJson(mediaJson(updatedAt: '2026-10-19T14:00:00Z'));
      await thumbs.thumbnail(v1);
      expect(downloads, 1);

      // El medio se reemplazo: updated_at distinto -> descarga fresca.
      final v2 = Media.fromJson(mediaJson(updatedAt: '2026-10-20T10:00:00Z'));
      final fresh = await thumbs.thumbnail(v2);
      expect(fresh, isNotNull);
      expect(downloads, 2);
    });

    test('video y url no tienen miniatura (limitacion documentada)',
        () async {
      var anyRequest = false;
      final client = MockClient((request) async {
        anyRequest = true;
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      });
      final thumbs = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: _thumbnailDir(),
      );

      final video = Media.fromJson(mediaJson(
        name: 'Clip.mp4',
        mediaType: 'video',
        mimeType: 'video/mp4',
        fileSize: 12,
      ));
      final url = Media.fromJson(mediaJson(
        name: 'Enlace',
        mediaType: 'url',
        mimeType: null,
        fileSize: null,
        storageKey: null,
        externalUrl: 'https://ejemplo.org',
      ));

      expect(await thumbs.thumbnail(video), isNull);
      expect(await thumbs.thumbnail(url), isNull);
      expect(anyRequest, isFalse); // sin descargas de video ni de url
    });

    test('evicta del disco por LRU cuando se excede el limite',
        () async {
      final original = await pngBytes(width: 32, height: 32);
      final dir = _thumbnailDir();
      final client = _fileClient(original);
      final thumbs = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: dir,
        memoryMaxEntries: 1,
        diskMaxEntries: 2,
        diskMaxBytes: 1024 * 1024,
      );

      final a = Media.fromJson(mediaJson(id: 1));
      final b = Media.fromJson(mediaJson(id: 2, name: 'b.png'));
      final c = Media.fromJson(mediaJson(id: 3, name: 'c.png'));

      await thumbs.thumbnail(a);
      await thumbs.thumbnail(b);
      await thumbs.thumbnail(c); // excede 2 entradas: a es la mas vieja

      final pngFiles = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(pngFiles, hasLength(2));
      expect(pngFiles.any((f) => f.contains('_1_')), isFalse);
      expect(pngFiles.any((f) => f.contains('_2_')), isTrue);
      expect(pngFiles.any((f) => f.contains('_3_')), isTrue);
    });

    test('la memoria limitada cae al disco sin descargar de nuevo',
        () async {
      final original = await pngBytes(width: 32, height: 32);
      var downloads = 0;
      final client = _fileClient(original, onDownload: (d) => downloads = d);
      final thumbs = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: _thumbnailDir(),
        memoryMaxEntries: 1,
      );
      final a = Media.fromJson(mediaJson(id: 1));
      final b = Media.fromJson(mediaJson(id: 2, name: 'b.png'));

      await thumbs.thumbnail(a); // descarga 1
      await thumbs.thumbnail(b); // descarga 2; evicta a de memoria
      final again = await thumbs.thumbnail(a); // hit de disco

      expect(again, isNotNull);
      expect(downloads, 2); // sin tercera descarga
    });

    test('llamadas concurrentes deduplican la descarga', () async {
      final original = await pngBytes(width: 32, height: 32);
      var downloads = 0;
      final client = _fileClient(original, onDownload: (d) => downloads = d);
      final thumbs = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: _thumbnailDir(),
      );
      final media = Media.fromJson(mediaJson());

      final results = await Future.wait([
        thumbs.thumbnail(media),
        thumbs.thumbnail(media),
        thumbs.thumbnail(media),
      ]);

      expect(results.whereType<Uint8List>(), hasLength(3));
      expect(downloads, 1);
    });

    test('removeMedia limpia sus entradas de disco', () async {
      final original = await pngBytes(width: 32, height: 32);
      final dir = _thumbnailDir();
      final client = _fileClient(original);
      final thumbs = ThumbnailService(
        service: MediaService(client: _apiClient(client)),
        cacheDirectory: dir,
      );
      final media = Media.fromJson(mediaJson(id: 5));

      await thumbs.thumbnail(media);
      expect(
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')),
        isNotEmpty,
      );

      await thumbs.removeMedia(5);

      expect(
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')),
        isEmpty,
      );
    });
  });

  group('MediaService.validateUploadFile (antes del POST)', () {
    test('rechaza sin archivo', () {
      expect(MediaService.validateUploadFile('', 10), isNotNull);
    });

    test('rechaza extension no permitida antes de gastar la LAN', () {
      final error = MediaService.validateUploadFile('instalador.exe', 120);
      expect(error, contains('no es valida'));
    });

    test('rechaza por encima de 200 MB sin enviar nada', () {
      final error = MediaService.validateUploadFile(
        'gigante.mp4',
        MediaService.maxUploadBytes + 1,
      );
      expect(error, contains('200.0 MB'));
      expect(error, contains('rechazo antes'));
    });

    test('acepta los tipos permitidos por el backend', () {
      expect(MediaService.validateUploadFile('foto.JPG', 1024), isNull);
      expect(MediaService.validateUploadFile('clip.mkv', 1024), isNull);
      expect(MediaService.validateUploadFile('documento.pdf', 1024), isNull);
      expect(MediaService.mediaTypeForExtension('foto.JPG'), 'image');
      expect(MediaService.mediaTypeForExtension('clip.mkv'), 'video');
      expect(MediaService.mediaTypeForExtension('documento.pdf'), 'pdf');
    });
  });

  group('Progreso de subida multipart', () {
    test('onProgress reporta el avance hasta el total', () async {
      final client = MockClient((request) async => http.Response(
          jsonEncode({
            'id': 9,
            'name': 'Foto.png',
            'media_type': 'image',
            'mime_type': 'image/png',
            'file_size': 3000,
            'storage_key': 'images/9.png',
            'external_url': null,
            'created_at': '2026-10-19T14:00:00Z',
            'updated_at': '2026-10-19T14:00:00Z',
          }),
          201,
          headers: {'content-type': 'application/json'}));
      final service = MediaService(client: _apiClient(client));

      final progress = <(int, int)>[];
      final media = await service.uploadFile(
        bytes: Uint8List(3000),
        filename: 'Foto.png',
        mediaType: 'image',
        onProgress: (sent, total) => progress.add((sent, total)),
      );

      expect(media.id, 9);
      expect(progress, isNotEmpty);
      // El total es el del multipart completo (boundary + campos +
      // archivo); lo importante: llega al 100% y nunca lo supera.
      final total = progress.first.$2;
      expect(total, greaterThanOrEqualTo(3000));
      expect(progress.last.$1, total);
      for (final (sent, currentTotal) in progress) {
        expect(sent <= currentTotal, isTrue);
        expect(currentTotal, total);
      }
    });
  });

  group('MediaCard (data real del medio)', () {
    testWidgets('muestra miniatura real, nombre y linea de datos',
        (tester) async {
      // La generacion/decodificacion real del engine solo avanza
      // fuera del binding falso: pngBytes y el pre-calentamiento del
      // cache van dentro de runAsync.
      final original =
          await tester.runAsync(() => pngBytes(width: 640, height: 480)) ??
              Uint8List(0);
      var downloads = 0;
      final client = _fileClient(original, onDownload: (d) => downloads = d);
      final service = MediaService(client: _apiClient(client));
      final library = MediaLibraryController(
        service: service,
        thumbnails: ThumbnailService(
          service: service,
          cacheDirectory: _thumbnailDir(),
        ),
      );
      final media = Media.fromJson(mediaJson());

      await tester.runAsync(() async {
        final thumb = await library.thumbnails.thumbnail(media);
        expect(thumb, isNotNull); // la decodificacion real ocurrio
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: library),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [MediaCard(media: media)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Image), findsOneWidget); // miniatura real
      expect(find.text('Banner_Bienvenida.png'), findsOneWidget);
      // Sin peso ni fecha: solo nombre y la insignia de tipo con icono.
      expect(find.text(media.metaLine), findsNothing);
      expect(find.text('Enviar a dispositivo'), findsNothing);
      expect(find.byIcon(media.typeIcon), findsOneWidget);
      expect(find.text('IMAGEN'), findsNothing);
      expect(downloads, 1); // el hit de memoria no descarga de nuevo
    });

    testWidgets('video: lienzo de tipo sin miniatura, con su data',
        (tester) async {
      var anyRequest = false;
      final client = MockClient((request) async {
        anyRequest = true;
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      });
      final service = MediaService(client: _apiClient(client));
      final library = MediaLibraryController(
        service: service,
        thumbnails: ThumbnailService(
          service: service,
          cacheDirectory: _thumbnailDir(),
        ),
      );
      final media = Media.fromJson(mediaJson(
        name: 'Clip_Sala.mp4',
        mediaType: 'video',
        mimeType: 'video/mp4',
        fileSize: 12 * 1024 * 1024,
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: library),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [MediaCard(media: media)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Image), findsNothing); // sin miniatura fingida
      expect(find.text('Clip_Sala.mp4'), findsOneWidget);
      expect(find.text(media.metaLine), findsNothing); // sin peso ni fecha
      // Limitacion documentada, no un dato inventado.
      expect(find.text('Miniatura no disponible'), findsOneWidget);
      expect(anyRequest, isFalse); // nunca baja el video
    });

    testWidgets('url: recurso externo sin tamano de archivo',
        (tester) async {
      final client = MockClient((request) async => http.Response('[]', 200,
          headers: {'content-type': 'application/json'}));
      final service = MediaService(client: _apiClient(client));
      final library = MediaLibraryController(
        service: service,
        thumbnails: ThumbnailService(
          service: service,
          cacheDirectory: _thumbnailDir(),
        ),
      );
      final media = Media.fromJson(mediaJson(
        name: 'Loop externo',
        mediaType: 'url',
        mimeType: null,
        fileSize: null,
        storageKey: null,
        externalUrl: 'https://ejemplo.org/clip.mp4',
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: library),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [MediaCard(media: media)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Loop externo'), findsOneWidget);
      expect(media.metaLine, contains('Enlace'));
      expect(media.metaLine, contains('Recurso externo'));
      // La tarjeta no muestra el tamano externo.
      expect(find.text('EXTERNO'), findsNothing);
    });
  });
}
