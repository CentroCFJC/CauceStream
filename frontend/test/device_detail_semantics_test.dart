/// Regresion del detalle de dispositivo con semantica habilitada:
/// la pastilla de tipo sobre la vista previa (Stack + Positioned en
/// una columna con altura sin limitar) rompia el layout con
/// "BoxConstraints forces an infinite height" si se usaba
/// StackFit.expand. Debe pintarse sin excepciones.

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
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
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

Map<String, dynamic> _assignment() => {
      'id': 1,
      'device_id': 1,
      'device_uid': 'totem-sala-1',
      'media_id': 2,
      'media_name': 'Loop bienal',
      'sync_status': 'synchronized',
      'revision': 1,
      'created_at': '2026-10-20T10:00:00',
      'updated_at': '2026-10-27T10:00:00',
    };

Map<String, dynamic> _media() => {
      'id': 2,
      'name': 'Loop bienal',
      'media_type': 'video',
      'created_at': '2026-10-20T10:00:00',
      'updated_at': '2026-10-27T10:00:00',
    };

void main() {
  testWidgets('detalle: pastilla sobre vista previa sin assert de '
      'semantica', (tester) async {
    final semantics = tester.ensureSemantics();
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/devices') {
        return http.Response(
          jsonEncode([_device()]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/api/assignments') {
        return http.Response(
          jsonEncode([_assignment()]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path == '/api/media') {
        return http.Response(
          jsonEncode([_media()]),
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
        cacheDirectory: Directory.systemTemp.createTempSync('cauce_repro'),
      ),
    );
    await devices.refresh();
    await mediaLibrary.ensureLoaded();

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
          home: DeviceDetailScreen(device: Device.fromJson(_device())),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('REPRODUCIENDO AHORA'), findsOneWidget);
    semantics.dispose();
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
