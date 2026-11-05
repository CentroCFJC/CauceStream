// Verifica el shell principal: barra de 5 pestanas y el ciclo de
// sondeo del inventario (un solo Timer compartido, cancelado al
// desmontar).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/devices_controller.dart';
import 'package:cauce_stream/controllers/media_library_controller.dart';
import 'package:cauce_stream/core/app_info.dart';
import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/navigation/main_shell.dart';
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
import 'package:cauce_stream/session/session_controller.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/session/token_storage.dart';

void main() {
  testWidgets('el shell muestra la barra de navegacion y sondea el '
      'inventario', (tester) async {
    final requests = <http.Request>[];
    // El inventario y la biblioteca responden vacios: el shell solo
    // necesita que las pestanas puedan consultar sus controladores.
    final apiClient = ApiClient(
      baseUrl: 'http://10.15.1.150:8000/api',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final devices = DevicesController(
      service: DeviceService(client: apiClient),
    );
    final mediaService = MediaService(client: apiClient);
    final mediaLibrary = MediaLibraryController(
      service: mediaService,
      thumbnails: ThumbnailService(
        service: mediaService,
        cacheDirectory: Directory.systemTemp.createTempSync('cauce_thumbs'),
      ),
    );
    final session = SessionController(
      storage: _FakeStorage(),
      authService: AuthService(client: apiClient),
      userService: UserService(client: apiClient),
      apiClient: apiClient,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: session),
          ChangeNotifierProvider.value(value: devices),
          ChangeNotifierProvider.value(value: mediaLibrary),
        ],
        child: const MaterialApp(home: MainShell()),
      ),
    );
    await tester.pump();
    // Deja terminar la carga asincrona del inventario.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('${AppInfo.appName} ${AppInfo.appVersion}'),
        findsNothing);
    expect(find.text('- ${AppInfo.institution}'), findsNothing);

    // Barra de navegacion completa.
    for (final label in ['Inicio', 'Dispositivos', 'Biblioteca', 'Actividad', 'Mas']) {
      expect(find.text(label), findsWidgets);
    }

    // Sondeo periodico: el inventario se consulta de nuevo a los 10 s.
    int listCalls() => requests
        .where((r) => r.method == 'GET' && r.url.path == '/api/devices')
        .length;
    expect(listCalls(), 1);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 100));
    expect(listCalls(), 2);
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 100));
    expect(listCalls(), 3);

    // Navegar entre pestanas no dispara fetch duplicados: el
    // ensureLoaded salta el fetch porque los datos siguen frescos.
    await tester.tap(find.text('Biblioteca'));
    await tester.pump();
    expect(listCalls(), 3);

    // Al desmontar el shell el sondeo se detiene (sin timers huerfanos).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(listCalls(), 3);
  });
}

class _FakeStorage implements TokenStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readRememberedEmail() async => null;

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveSession(
      {required String token, String? rememberedEmail}) async {}
}
