// Pruebas de la biblioteca de medios (RF-008 fase 1):
// modelo Media, MediaService (incluida la subida multipart y el
// mapeo de 400/413), MediaLibraryController y la biblioteca en modo
// solo lectura.
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
import 'package:cauce_stream/core/network/api_exception.dart';
import 'package:cauce_stream/models/media.dart';
import 'package:cauce_stream/screens/media/media_library_screen.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/session/session_controller.dart';
import 'package:cauce_stream/session/token_storage.dart';

Map<String, dynamic> mediaJson({
  int id = 1,
  String name = 'Banner_Bienvenida.png',
  String mediaType = 'image',
  String? mimeType = 'image/png',
  int? fileSize = 8400,
  String? storageKey = 'media/1/banner.png',
  String? externalUrl,
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
      'updated_at': '2026-10-19T14:00:00Z',
    };

void main() {
  group('Media.fromJson', () {
    test('mapea el esquema MediaRead completo', () {
      final media = Media.fromJson(mediaJson());
      expect(media.id, 1);
      expect(media.name, 'Banner_Bienvenida.png');
      expect(media.mediaType, 'image');
      expect(media.mimeType, 'image/png');
      expect(media.fileSize, 8400);
      expect(media.storageKey, 'media/1/banner.png');
      expect(media.externalUrl, isNull);
      expect(media.createdAt, DateTime.parse('2026-10-19T14:00:00Z'));
    });

    test('defaults y helpers por tipo de medio', () {
      final url = Media.fromJson(mediaJson(
        name: 'Contenido externo',
        mediaType: 'url',
        mimeType: null,
        fileSize: null,
        storageKey: null,
        externalUrl: 'https://ejemplo.org/clip.mp4',
      ));
      expect(url.isUrl, isTrue);
      expect(url.isFile, isFalse);
      expect(url.readableSize, isNull);
      expect(url.typeLabel, 'Enlace');
      expect(url.subtitle, 'Enlace');
      expect(url.externalUrl, 'https://ejemplo.org/clip.mp4');

      final video = Media.fromJson(mediaJson(
        name: 'Clip.mp4',
        mediaType: 'video',
        mimeType: 'video/mp4',
        fileSize: 1024 * 1024 * 12,
      ));
      expect(video.isVideo, isTrue);
      expect(video.isFile, isTrue);
      expect(video.typeLabel, 'Video');
      expect(video.readableSize, '12.0 MB');
      expect(video.subtitle, 'video/mp4 - 12.0 MB');

      final small = Media.fromJson(mediaJson(fileSize: 512));
      expect(small.readableSize, '512 B');
    });
  });

  group('MediaService', () {
    test('listMedia envia limit y offset como query', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode([mediaJson()]), 200,
            headers: {'content-type': 'application/json'});
      });
      final service = _service(client);

      final media = await service.listMedia(limit: 25, offset: 50);

      expect(media, hasLength(1));
      expect(media.single.name, 'Banner_Bienvenida.png');
      expect(requested!.path, '/api/media');
      expect(requested!.queryParameters['limit'], '25');
      expect(requested!.queryParameters['offset'], '50');
    });

    test('getMediaFileBytes baja el binario autenticado', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3, 4]),
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final service = _service(client, token: 'jwt-de-sesion');

      final bytes = await service
          .getMediaFileBytes(Media.fromJson(mediaJson()));

      expect(bytes, [1, 2, 3, 4]);
      expect(requests.single.url.path, '/api/media/1/file');
      expect(requests.single.headers['Authorization'], 'Bearer jwt-de-sesion');
    });

    test('registerUrl envia el contrato JSON de /media/urls', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode(mediaJson(
                name: 'Enlace', mediaType: 'url', mimeType: 'video/mp4')),
            201,
            headers: {'content-type': 'application/json'});
      });
      final service = _service(client);

      final media = await service.registerUrl(
        name: 'Enlace',
        url: 'https://ejemplo.org/clip.mp4',
        mimeType: 'video/mp4',
      );

      expect(media.mediaType, 'url');
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/media/urls');
      expect(jsonDecode(captured!.body), {
        'name': 'Enlace',
        'url': 'https://ejemplo.org/clip.mp4',
        'mime_type': 'video/mp4',
      });
    });

    test('deleteMedia envia DELETE al id', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final service = _service(client);

      await service.deleteMedia(7);

      expect(captured!.method, 'DELETE');
      expect(captured!.url.path, '/api/media/7');
    });

    test('uploadFile envia multipart con token, campos y archivo',
        () async {
      // MockClient serializa el multipart: el handler recibe un
      // Request cuyo cuerpo es el MIME completo.
      http.Request? captured;
      String? contentType;
      final client = MockClient((request) async {
        captured = request;
        contentType = request.headers['content-type'];
        return http.Response(jsonEncode(mediaJson()), 201,
            headers: {'content-type': 'application/json'});
      });
      final service = _service(client, token: 'jwt-de-sesion');
      final bytes = Uint8List.fromList([9, 9, 9]);

      final media = await service.uploadFile(
        bytes: bytes,
        filename: 'FOTO_SALA.png',
        mediaType: 'image',
        name: 'Foto de sala',
      );

      expect(media.name, 'Banner_Bienvenida.png');
      final request = captured!;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/media');
      expect(request.headers['Authorization'], 'Bearer jwt-de-sesion');
      expect(contentType, startsWith('multipart/form-data; boundary='));
      final body = latin1.decode(request.bodyBytes);
      expect(body, contains('name="media_type"'));
      expect(body, contains('name="name"'));
      expect(body, contains('Foto de sala'));
      expect(body, contains('filename="FOTO_SALA.png"'));
      expect(body, contains('name="file"'));
      // Los bytes del archivo viajan dentro del cuerpo (0x09 = tab).
      expect(body, contains('\t\t\t'));
    });

    test('un 413 del servidor se expone con su detail', () async {
      final client = MockClient((request) async => http.Response(
          jsonEncode({
            'code': 'payload_too_large',
            'detail': 'El archivo supera el limite de 200 MB.'
          }),
          413,
          headers: {'content-type': 'application/json'}));
      final service = _service(client);

      await expectLater(
        service.uploadFile(
          bytes: Uint8List.fromList([1]),
          filename: 'gigante.mp4',
          mediaType: 'video',
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 413)
            .having((e) => e.code, 'code', 'payload_too_large')
            .having((e) => e.message, 'message',
                'El archivo supera el limite de 200 MB.')),
      );
    });

    test('un 400 del servidor se expone con su detail', () async {
      final client = MockClient((request) async => http.Response(
          jsonEncode({
            'code': 'bad_request',
            'detail': 'La extension .exe no es valida para una imagen.'
          }),
          400,
          headers: {'content-type': 'application/json'}));
      final service = _service(client);

      await expectLater(
        service.registerUrl(name: 'x', url: 'https://a.b/c'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message',
                'La extension .exe no es valida para una imagen.')),
      );
    });
  });

  group('MediaLibraryController', () {
    test('refresh carga la lista y detecta pagina completa', () async {
      final client = MockClient((request) async {
        final offset = int.parse(request.url.queryParameters['offset']!);
        if (offset == 0) {
          return http.Response(
              jsonEncode(
                  List.generate(50, (i) => mediaJson(id: i, name: 'm$i'))),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode([mediaJson(id: 99, name: 'extra')]),
            200,
            headers: {'content-type': 'application/json'});
      });
      final controller = _library(client);

      await controller.refresh();
      expect(controller.status, MediaLibraryStatus.ready);
      expect(controller.media, hasLength(50));
      expect(controller.hasMore, isTrue);

      await controller.loadMore();
      expect(controller.media, hasLength(51));
      expect(controller.media.last.name, 'extra');
      expect(controller.hasMore, isFalse);
    });

    test('refresh nunca lanza con el servidor caido', () async {
      final client = MockClient((request) async {
        throw http.ClientException('servidor caido');
      });
      final controller = _library(client);

      await controller.refresh();

      expect(controller.status, MediaLibraryStatus.error);
      expect(controller.errorMessage, isNotNull);
      expect(controller.media, isEmpty);
    });

    test('remove borra y recarga del servidor', () async {
      final deleted = <int>[];
      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted.add(int.parse(request.url.path.split('/').last));
          return http.Response('', 204);
        }
        return http.Response(
            jsonEncode([
              mediaJson(id: 1, name: 'Banner'),
              mediaJson(id: 2, name: 'otro'),
            ].where((m) => !deleted.contains(m['id'])).toList()),
            200,
            headers: {'content-type': 'application/json'});
      });
      final controller = _library(client);

      await controller.refresh();
      expect(controller.media, hasLength(2));

      final ok = await controller.remove(Media.fromJson(mediaJson()));

      expect(ok, isTrue);
      expect(deleted, [1]);
      expect(controller.media.map((m) => m.id), everyElement(isNot(1)));
    });

    test('remove expone el fallo sin lanzar', () async {
      final client = MockClient((request) async {
        if (request.method == 'DELETE') {
          return http.Response(
              jsonEncode({
                'code': 'not_found',
                'detail': 'El medio ya no existe.'
              }),
              404,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      });
      final controller = _library(client);

      final ok = await controller.remove(Media.fromJson(mediaJson()));

      expect(ok, isFalse);
      expect(controller.errorMessage, 'El medio ya no existe.');
    });
  });

  group('MediaLibraryScreen (solo lectura)', () {
    testWidgets('muestra los medios del servidor y oculta la subida '
        'para un mediador', (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/media') {
          return http.Response(
              jsonEncode([
                mediaJson(id: 1, name: 'Banner_Bienvenida.png'),
                mediaJson(
                    id: 2,
                    name: 'Enlace externo',
                    mediaType: 'url',
                    mimeType: null,
                    fileSize: null,
                    storageKey: null,
                    externalUrl: 'https://ejemplo.org'),
              ]),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      });
      final apiClient = ApiClient(
        baseUrl: 'http://10.15.1.150:8000/api',
        client: client,
      );
      // Sesion sin usuario cargado: equivalente a un mediador
      // (isAdmin false, sin `content.manage`).
      final session = SessionController(
        storage: _FakeStorage(),
        authService: AuthService(client: apiClient),
        userService: UserService(client: apiClient),
        apiClient: apiClient,
      );
      final mediaService = MediaService(client: apiClient);
      final library = MediaLibraryController(
        service: mediaService,
        thumbnails: ThumbnailService(
          service: mediaService,
          cacheDirectory: _thumbnailDir(),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: session),
            ChangeNotifierProvider.value(value: library),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MediaLibraryScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Banner_Bienvenida.png'), findsOneWidget);
      expect(find.text('Enlace externo'), findsOneWidget);
      // Mediador: sin boton de subida ni de eliminacion.
      expect(find.text('Nuevo Medio'), findsNothing);
    });

    testWidgets('las tarjetas ocupan el 50% del ancho (dos por fila), '
        'con insignia de tipo solo icono y sin peso, fecha ni envio',
        (tester) async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/media') {
          return http.Response(
              jsonEncode([
                mediaJson(id: 1, name: 'Banner_Bienvenida.png'),
                mediaJson(
                    id: 2,
                    name: 'Clip_Sala.mp4',
                    mediaType: 'video',
                    mimeType: 'video/mp4',
                    fileSize: 12 * 1024 * 1024),
              ]),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      });
      final apiClient = ApiClient(
        baseUrl: 'http://10.15.1.150:8000/api',
        client: client,
      );
      final session = SessionController(
        storage: _FakeStorage(),
        authService: AuthService(client: apiClient),
        userService: UserService(client: apiClient),
        apiClient: apiClient,
      );
      final mediaService = MediaService(client: apiClient);
      final library = MediaLibraryController(
        service: mediaService,
        thumbnails: ThumbnailService(
          service: mediaService,
          cacheDirectory: _thumbnailDir(),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: session),
            ChangeNotifierProvider.value(value: library),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MediaLibraryScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Dos tarjetas, cada una con el 50% del ancho de contenido
      // (800 - 24*2 = 752; (752 - 12) / 2 = 370), en la misma fila.
      expect(find.byType(MediaCard), findsNWidgets(2));
      final first = tester.getRect(find.byType(MediaCard).first);
      final second = tester.getRect(find.byType(MediaCard).at(1));
      expect(first.width, moreOrLessEquals(370, epsilon: 1));
      expect(second.width, moreOrLessEquals(first.width, epsilon: 0.5));
      expect(second.top, moreOrLessEquals(first.top, epsilon: 1));
      expect(second.left - first.left, moreOrLessEquals(first.width + 12, epsilon: 1));

      // Sin peso, fecha ni boton de envio; el tipo va solo con icono.
      expect(find.text('Enviar a dispositivo'), findsNothing);
      expect(find.textContaining('8 KB'), findsNothing);
      expect(find.textContaining('12.0 MB'), findsNothing);
      expect(find.text('IMAGEN'), findsNothing);
      expect(find.text('VIDEO'), findsNothing);
      expect(find.byIcon(Icons.image), findsWidgets);
      expect(find.byIcon(Icons.movie), findsWidgets);
      expect(find.text('Banner_Bienvenida.png'), findsOneWidget);
      expect(find.text('Clip_Sala.mp4'), findsOneWidget);
    });

    testWidgets('muestra el estado de error con reintento si el '
        'servidor no responde', (tester) async {
      final client = MockClient((request) async {
        throw http.ClientException('servidor caido');
      });
      final apiClient = ApiClient(
        baseUrl: 'http://10.15.1.150:8000/api',
        client: client,
      );
      final session = SessionController(
        storage: _FakeStorage(),
        authService: AuthService(client: apiClient),
        userService: UserService(client: apiClient),
        apiClient: apiClient,
      );
      final mediaService = MediaService(client: apiClient);
      final library = MediaLibraryController(
        service: mediaService,
        thumbnails: ThumbnailService(
          service: mediaService,
          cacheDirectory: _thumbnailDir(),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: session),
            ChangeNotifierProvider.value(value: library),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MediaLibraryScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Nuevo Medio'), findsNothing);
    });

    testWidgets('un medio nuevo en el listado pide su propia '
        'miniatura (no hereda la de otra tarjeta)', (tester) async {
      // PNG real: la decodificacion y la carga del indice del cache
      // son llamadas al engine/I/O que solo avanzan fuera del
      // binding falso (runAsync).
      final png = await tester.runAsync(() => _testPng()) ??
          Uint8List.fromList([1]);
      var listBody = jsonEncode([mediaJson(id: 1, name: 'primero.png')]);
      final downloadedIds = <int>[];
      final client = MockClient((request) async {
        final fileMatch =
            RegExp(r'^/api/media/(\d+)/file$').firstMatch(request.url.path);
        if (fileMatch != null) {
          downloadedIds.add(int.parse(fileMatch.group(1)!));
          return http.Response.bytes(png, 200,
              headers: {'content-type': 'image/png'});
        }
        return http.Response(listBody, 200,
            headers: {'content-type': 'application/json'});
      });
      final apiClient = ApiClient(
        baseUrl: 'http://10.15.1.150:8000/api',
        client: client,
      );
      final session = SessionController(
        storage: _FakeStorage(),
        authService: AuthService(client: apiClient),
        userService: UserService(client: apiClient),
        apiClient: apiClient,
      );
      final mediaService = MediaService(client: apiClient);
      final library = MediaLibraryController(
        service: mediaService,
        thumbnails: ThumbnailService(
          service: mediaService,
          cacheDirectory: _thumbnailDir(),
        ),
      );

      // Precalienta la miniatura del primer medio (descarga id 1).
      await tester.runAsync(() async {
        final first = Media.fromJson(mediaJson(id: 1, name: 'primero.png'));
        expect(await library.thumbnails.thumbnail(first), isNotNull);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: session),
            ChangeNotifierProvider.value(value: library),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MediaLibraryScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // La tarjeta del primer medio uso el cache: sin nueva descarga.
      expect(downloadedIds, [1]);

      // Se sube un medio nuevo: queda arriba en la lista recargada.
      listBody = jsonEncode([
        mediaJson(id: 2, name: 'nuevo.png'),
        mediaJson(id: 1, name: 'primero.png'),
      ]);
      await library.refresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // La tarjeta nueva pidio SU binario; la de 'primero' conservo
      // su estado sin redescargar.
      expect(downloadedIds, [1, 2]);
    });
  });
}

MediaService _service(http.Client client, {String? token}) {
  final apiClient = ApiClient(
    baseUrl: 'http://10.15.1.150:8000/api',
    client: client,
  )..accessToken = token;
  return MediaService(client: apiClient);
}

MediaLibraryController _library(http.Client client, {String? token}) {
  final service = _service(client, token: token);
  return MediaLibraryController(
    service: service,
    thumbnails: ThumbnailService(
      service: service,
      cacheDirectory: _thumbnailDir(),
    ),
  );
}

/// Directorio fresco por test: el cache de disco nunca comparte
/// estado entre pruebas.
Directory _thumbnailDir() =>
    Directory.systemTemp.createTempSync('cauce_thumbs_test');

/// PNG real generado con el engine (PictureRecorder): unico metodo
/// disponible en tests para producir bytes decodificables.
Future<Uint8List> _testPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 40, 20), Paint()..color = const Color(0xFF3366CC));
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 20);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

class _FakeStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readRememberedEmail() async => null;

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveSession({required String token, String? rememberedEmail}) async {}
}
