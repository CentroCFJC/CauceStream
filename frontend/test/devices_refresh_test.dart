/// Refresh del inventario de dispositivos: la carga inicial es la
/// unica que puede mostrar pantalla de carga completa; con un sondeo
/// previo (aunque la lista este vacia) los refreshes son en segundo
/// plano y la UI nunca se tapa. El boton de refresh manual de la
/// pestana Dispositivos dispara GET /api/devices.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/devices_controller.dart';
import 'package:cauce_stream/controllers/media_library_controller.dart';
import 'package:cauce_stream/controllers/room_controller.dart';
import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/screens/devices/devices_screen.dart';
import 'package:cauce_stream/services/assignment_service.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/room_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/session/session_controller.dart';
import 'package:cauce_stream/session/token_storage.dart';

const _json = {'content-type': 'application/json'};

void main() {
  group('DevicesController.refresh', () {
    test('carga inicial con lista vacia: loading durante el fetch y '
        'ready al terminar', () async {
      final client = MockClient((request) async {
        return http.Response('[]', 200, headers: _json);
      });
      final api = ApiClient(baseUrl: 'http://server:8000/api', client: client);
      final controller = DevicesController(service: DeviceService(client: api));

      final pending = controller.refresh();
      expect(controller.status, DevicesLoadStatus.loading);
      expect(controller.isRefreshing, isTrue);
      await pending;
      expect(controller.status, DevicesLoadStatus.ready);
      expect(controller.devices, isEmpty);
      expect(controller.fetchedAt, isNotNull);
      expect(controller.isRefreshing, isFalse);
    });

    test('lista vacia ya cargada: el refresh nunca vuelve a loading', () async {
      var calls = 0;
      final second = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path == '/api/devices') {
          calls++;
          if (calls == 1) return http.Response('[]', 200, headers: _json);
          return second.future;
        }
        return http.Response('[]', 200, headers: _json);
      });
      final api = ApiClient(baseUrl: 'http://server:8000/api', client: client);
      final controller = DevicesController(service: DeviceService(client: api));

      await controller.refresh();
      expect(controller.devices, isEmpty);
      expect(controller.fetchedAt, isNotNull);

      // Segundo sondeo con la lista aun vacia: no hay pantalla de
      // carga, solo el indicador inline.
      final pending = controller.refresh();
      expect(controller.status, DevicesLoadStatus.ready);
      expect(controller.isRefreshing, isTrue);
      second.complete(http.Response('[]', 200, headers: _json));
      await pending;
      expect(controller.status, DevicesLoadStatus.ready);
      expect(controller.isRefreshing, isFalse);
      expect(calls, 2);
    });

    test('fallo sin datos previos -> error; con datos previos -> ready '
        'con errorMessage (la lista no se vacia)', () async {
      var up = true;
      final client = MockClient((request) async {
        if (!up) throw http.ClientException('servidor caido');
        return http.Response('[]', 200, headers: _json);
      });
      final api = ApiClient(baseUrl: 'http://server:8000/api', client: client);
      final controller = DevicesController(service: DeviceService(client: api));

      up = false;
      await controller.refresh();
      expect(controller.status, DevicesLoadStatus.error);
      expect(controller.fetchedAt, isNull);

      up = true;
      await controller.refresh();
      expect(controller.status, DevicesLoadStatus.ready);

      up = false;
      await controller.refresh();
      expect(
        controller.status,
        DevicesLoadStatus.ready,
        reason: 'con sondeo previo el fallo no rompe la pantalla',
      );
      expect(controller.errorMessage, isNotNull);
      expect(controller.devices, isEmpty);
    });
  });

  group('Pestana Dispositivos', () {
    testWidgets('carga inicial pendiente: pantalla de carga completa', (
      tester,
    ) async {
      final first = Completer<http.Response>();
      var devicesCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/devices') {
          devicesCalls++;
          return first.future;
        }
        return http.Response('[]', 200, headers: _json);
      });
      final api = ApiClient(baseUrl: 'http://server:8000/api', client: client);
      final devices = DevicesController(
        service: DeviceService(client: api),
        assignmentService: AssignmentService(client: api),
      );
      final media = _mediaLibrary(api);

      await tester.pumpWidget(_buildApp(api, devices, media));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Sin ningun sondeo previo si hay spinner a pantalla completa.
      expect(
        find.descendant(
          of: find.byType(Center),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      first.complete(http.Response('[]', 200, headers: _json));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(devicesCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('Todavia no hay dispositivos registrados'),
        findsOneWidget,
      );
    });

    testWidgets('con inventario vacio, el boton refresh pega en '
        '/api/devices sin tapar la UI (FAB y aviso siguen visibles)', (
      tester,
    ) async {
      var devicesCalls = 0;
      final second = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path == '/api/devices') {
          devicesCalls++;
          if (devicesCalls == 1) {
            return http.Response('[]', 200, headers: _json);
          }
          return second.future;
        }
        return http.Response('[]', 200, headers: _json);
      });
      final api = ApiClient(baseUrl: 'http://server:8000/api', client: client);
      final devices = DevicesController(
        service: DeviceService(client: api),
        assignmentService: AssignmentService(client: api),
      );
      final media = _mediaLibrary(api);

      await tester.pumpWidget(_buildApp(api, devices, media));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(devicesCalls, 1);
      expect(
        find.textContaining('Todavia no hay dispositivos registrados'),
        findsOneWidget,
      );
      expect(find.text('Nuevo Dispositivo'), findsOneWidget);

      // Refresh manual: segunda peticion a /api/devices, pendiente.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(devicesCalls, 2, reason: 'el boton dispara GET /api/devices');

      // Mientras tanto la UI no se reemplaza por un spinner: el aviso
      // y el boton de registro siguen ahi, y el unico indicador es el
      // del boton de refresh.
      expect(
        find.descendant(
          of: find.byType(Center),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(
        find.textContaining('Todavia no hay dispositivos registrados'),
        findsOneWidget,
      );
      expect(find.text('Nuevo Dispositivo'), findsOneWidget);

      second.complete(http.Response('[]', 200, headers: _json));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(devices.status, DevicesLoadStatus.ready);
      expect(devices.isRefreshing, isFalse);
    });
  });
}

MediaLibraryController _mediaLibrary(ApiClient api) {
  final mediaService = MediaService(client: api);
  return MediaLibraryController(
    service: mediaService,
    thumbnails: ThumbnailService(
      service: mediaService,
      cacheDirectory: Directory.systemTemp.createTempSync('cauce_refresh'),
    ),
  );
}

Widget _buildApp(
  ApiClient api,
  DevicesController devices,
  MediaLibraryController media,
) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SessionController>.value(
        value: _FakeSession(apiClient: api),
      ),
      ChangeNotifierProvider.value(value: devices),
      ChangeNotifierProvider.value(value: media),
      ChangeNotifierProvider.value(
        value: RoomController(service: RoomService(client: api)),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: DevicesScreen())),
  );
}

class _FakeSession extends SessionController {
  _FakeSession({required ApiClient apiClient})
    : super(
        storage: _FakeStorage(),
        authService: AuthService(client: apiClient),
        userService: UserService(client: apiClient),
        apiClient: apiClient,
      );

  @override
  bool get isAdmin => true;
}

class _FakeStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readRememberedEmail() async => null;

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveSession({
    required String token,
    String? rememberedEmail,
  }) async {}
}
