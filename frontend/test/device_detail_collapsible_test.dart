/// Panel INFORMACION del detalle de dispositivo: debe nacer PLEGADO,
/// quedar debajo de las ACCIONES y desplegarse al tocar su cabecera.

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
import 'package:cauce_stream/services/assignment_service.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/session/session_controller.dart';
import 'package:cauce_stream/session/token_storage.dart';

Map<String, dynamic> _device() => {
  'id': 1,
  'device_uid': 'totem-sala-1',
  'name': 'Totem Sala 1',
  'type': 'TV',
  'status': 'online',
  'device_state': 'active',
  'ws_connected': true,
  'ip_address': '10.15.1.10',
  'created_at': '2026-10-20T10:00:00',
  'updated_at': '2026-10-27T10:00:00',
};

void main() {
  testWidgets('el panel INFORMACION nace plegado, debajo de ACCIONES, '
      'y se despliega al tocar la cabecera', (tester) async {
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/devices') {
        return http.Response(
          jsonEncode([_device()]),
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
    final api = ApiClient(baseUrl: 'http://server:8000/api', client: client);
    final mediaService = MediaService(client: api);
    final devices = DevicesController(
      service: DeviceService(client: api),
      assignmentService: AssignmentService(client: api),
    );
    final mediaLibrary = MediaLibraryController(
      service: mediaService,
      thumbnails: ThumbnailService(
        service: mediaService,
        cacheDirectory: Directory.systemTemp.createTempSync('cauce_collapse'),
      ),
    );
    await devices.refresh();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionController>.value(
            value: _FakeSession(apiClient: api),
          ),
          ChangeNotifierProvider.value(value: devices),
          ChangeNotifierProvider.value(value: mediaLibrary),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DeviceDetailScreen(device: Device.fromJson(_device())),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // La cabecera del panel existe, pero el contenido nace plegado.
    expect(find.text('INFORMACION'), findsOneWidget);
    expect(find.text('DIRECCION IP'), findsNothing);

    // El panel queda DEBAJO de las acciones en la columna.
    final accionesY = tester.getTopLeft(find.text('ACCIONES')).dy;
    final infoY = tester.getTopLeft(find.text('INFORMACION')).dy;
    expect(
      infoY,
      greaterThan(accionesY),
      reason: 'INFORMACION debe ir despues de ACCIONES',
    );

    // Al tocar la cabecera se despliega y muestra los datos.
    await tester.ensureVisible(find.text('INFORMACION'));
    await tester.tap(find.text('INFORMACION'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('DIRECCION IP'), findsOneWidget);
    expect(find.text('10.15.1.10'), findsOneWidget);

    // Un segundo toque lo vuelve a plegar (sin abrir el dialogo de edicion).
    await tester.ensureVisible(find.text('INFORMACION'));
    await tester.tap(find.text('INFORMACION'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('DIRECCION IP'), findsNothing);
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
