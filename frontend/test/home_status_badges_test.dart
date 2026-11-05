/// Pastillas de estado de la pantalla de Inicio: deben mostrar las
/// tres categorias reales del inventario (Activos, En espera,
/// Desconectados) con los conteos de DevicesController, y el banner
/// debe usar el mismo vocabulario. Un dispositivo online con
/// device_state nulo cuenta como activo.

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
import 'package:cauce_stream/screens/home/home_screen.dart';
import 'package:cauce_stream/services/assignment_service.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/session/session_controller.dart';
import 'package:cauce_stream/session/token_storage.dart';

Map<String, dynamic> _device(
  int id,
  String uid,
  String status,
  String? deviceState,
) =>
    {
      'id': id,
      'device_uid': uid,
      'name': uid,
      'type': 'TV',
      'status': status,
      'device_state': deviceState,
      'ws_connected': true,
      'created_at': '2026-10-20T10:00:00',
      'updated_at': '2026-10-27T10:00:00',
    };

void main() {
  testWidgets('las tres pastillas muestran Activos, En espera y '
      'Desconectados con los conteos reales', (tester) async {
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/devices') {
        return http.Response(
          jsonEncode([
            _device(1, 'tv-activa', 'online', 'active'),
            _device(2, 'tv-sin-estado', 'online', null),
            _device(3, 'tv-espera', 'online', 'idle'),
            _device(4, 'tv-caida', 'offline', null),
          ]),
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
    final devices = DevicesController(
      service: DeviceService(client: api),
      assignmentService: AssignmentService(client: api),
    );
    final mediaLibrary = MediaLibraryController(
      service: MediaService(client: api),
      thumbnails: ThumbnailService(
        service: MediaService(client: api),
        cacheDirectory: Directory.systemTemp.createTempSync('cauce_home'),
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
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Subtitulo y total de dispositivos registrados.
    expect(find.text('RESUMEN GENERAL'), findsOneWidget);
    expect(find.text('4 dispositivos registrados'), findsOneWidget);

    // Las tres pastillas usan iconografia, no palabras.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    // La semántica conserva las categorias con sus conteos.
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('2 activos'), findsOneWidget);
    expect(find.bySemanticsLabel('1 en espera'), findsOneWidget);
    expect(find.bySemanticsLabel('1 desconectados'), findsOneWidget);
    semantics.dispose();

    // El vocabulario viejo ya no aparece, ni el banner de sala, ni el
    // boton "Ver todas" junto a DISPOSITIVOS.
    expect(find.text('ACTIVOS'), findsNothing);
    expect(find.text('EN LINEA'), findsNothing);
    expect(find.text('OFFLINE'), findsNothing);
    expect(find.text('ESTADO DE LA SALA'), findsNothing);
    expect(find.text('DISPOSITIVOS'), findsOneWidget);
    expect(find.text('Ver todas'), findsNothing);

    // Conteos en las pastillas (2, 1, 1) como Text puros.
    expect(find.text('2'), findsWidgets);
    expect(find.text('1'), findsWidgets);

    // Iconografia de dispositivos nueva (la misma del registro):
    // icono Material por tipo en cada fila; los assets antiguos de
    // estacion ya no aparecen en ninguna parte.
    expect(find.byIcon(Icons.tv), findsNWidgets(3));
    // Fila del dispositivo caido + tarjeta de alerta urgente.
    expect(find.byIcon(Icons.tv_off), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName.contains('Iconos_Dispositivos'),
      ),
      findsNothing,
    );
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
