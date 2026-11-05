/// Tests de frescura del inventario (Etapa C del blindaje del canal
/// WS): `isStale` declara la edad del conocimiento cuando el sondeo
/// del servidor falla, SIN cambiar el estado de ningun dispositivo.
/// La UI lo traduce en el aviso compartido y en pills atenuadas.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/devices_controller.dart';
import 'package:cauce_stream/controllers/media_library_controller.dart';
import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/models/device.dart';
import 'package:cauce_stream/screens/devices/device_detail_screen.dart';
import 'package:cauce_stream/widgets/device_connection_status.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/assignment_service.dart';
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/session/session_controller.dart';
import 'package:cauce_stream/session/token_storage.dart';

Map<String, dynamic> _deviceJson({String status = 'online'}) => {
      'id': 1,
      'device_uid': 'totem-sala-1',
      'name': 'Totem Sala 1',
      'type': 'TV',
      'status': status,
      'device_state': 'active',
      'ws_connected': true,
      'ip_address': '10.15.1.10',
      'created_at': '2026-10-20T10:00:00',
      'updated_at': '2026-10-27T10:00:00',
    };

http.Client _client({bool Function()? down}) {
  return MockClient((request) async {
    if (down != null && down()) {
      throw http.ClientException('servidor caido');
    }
    if (request.url.path == '/api/devices') {
      return http.Response(
        jsonEncode([_deviceJson()]),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path == '/api/assignments') {
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '[]',
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('DevicesController.isStale', () {
    test('fresco tras un sondeo exitoso, caducado al fallar un rato, '
        'fresco de nuevo al volver el servidor', () async {
      var up = true;
      final api = ApiClient(baseUrl: 'http://server:8000/api', client: _client(
        down: () => !up,
      ));
      var now = DateTime(2026, 10, 28, 10, 0, 0);
      final controller = DevicesController(
        service: DeviceService(client: api),
        now: () => now,
      );

      // Nunca sondeado: sin datos no hay foto antigua que mostrar.
      expect(controller.isStale, isFalse);

      await controller.refresh();
      expect(controller.isStale, isFalse);
      // El estado del dispositivo es el del servidor: no se toca.
      expect(controller.devices.single.isOnline, isTrue);

      // El servidor cae y pasa el umbral: el conocimiento caduca,
      // pero el snapshot NO se convierte en "desconectado".
      up = false;
      await controller.refresh();
      now = now.add(const Duration(seconds: 31));
      expect(controller.isStale, isTrue);
      expect(controller.devices.single.isOnline, isTrue,
          reason: 'isStale nunca muta el estado del dispositivo');

      // Vuelve el servidor: el sondeo refresca y sale de la caducidad.
      up = true;
      await controller.refresh();
      expect(controller.isStale, isFalse);
    });

    test('isStale es ortogonal a wsConnected: caduca sin tocar el canal',
        () async {
      final api = ApiClient(
        baseUrl: 'http://server:8000/api',
        client: _client(),
      );
      var now = DateTime(2026, 10, 28, 10, 0, 0);
      final controller = DevicesController(
        service: DeviceService(client: api),
        now: () => now,
      );
      await controller.refresh();
      expect(controller.devices.single.wsConnected, isTrue);

      now = now.add(const Duration(seconds: 31));
      expect(controller.isStale, isTrue);
      expect(controller.devices.single.wsConnected, isTrue,
          reason: 'la caducidad no falsifica el canal reportado');
    });
  });

  group('UI de datos caducados (detalle de dispositivo)', () {
    testWidgets('con sondeo caducado aparece el aviso y el indicador de '
        'conectividad se atenua; al refrescar desaparece', (tester) async {
      var up = true;
      final api = ApiClient(baseUrl: 'http://server:8000/api', client: _client(
        down: () => !up,
      ));
      var now = DateTime(2026, 10, 28, 10, 0, 0);
      final devices = DevicesController(
        service: DeviceService(client: api),
        assignmentService: AssignmentService(client: api),
        now: () => now,
      );
      final mediaService = MediaService(client: api);
      final mediaLibrary = MediaLibraryController(
        service: mediaService,
        thumbnails: ThumbnailService(
          service: mediaService,
          cacheDirectory: Directory.systemTemp.createTempSync('cauce_stale'),
        ),
      );
      await devices.refresh();

      Widget build() => MultiProvider(
            providers: [
              ChangeNotifierProvider<SessionController>.value(
                value: _FakeSession(apiClient: api),
              ),
              ChangeNotifierProvider.value(value: devices),
              ChangeNotifierProvider.value(value: mediaLibrary),
            ],
            child: MaterialApp(
              home: DeviceDetailScreen(device: Device.fromJson(_deviceJson())),
            ),
          );

      await tester.pumpWidget(build());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Sin respuesta del servidor'), findsNothing,
          reason: 'sondeo fresco: sin aviso');

      // El servidor cae y el tiempo pasa: el aviso aparece.
      up = false;
      await devices.refresh();
      now = now.add(const Duration(seconds: 45));
      await tester.pumpWidget(build());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Sin respuesta del servidor'), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(DeviceConnectionStatus),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.55);

      // Vuelve el servidor: el aviso desaparece solo.
      up = true;
      await devices.refresh();
      await tester.pumpWidget(build());
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Sin respuesta del servidor'), findsNothing);
    });
  });
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
