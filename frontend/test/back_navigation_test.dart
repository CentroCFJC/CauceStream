// Retroceso del sistema (boton fisico o gesto) sobre el shell: debe
// volver a la pestana anterior segun el historial, nunca cerrar la
// app mientras quede historial.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/devices_controller.dart';
import 'package:cauce_stream/controllers/media_library_controller.dart';
import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/navigation/main_shell.dart';
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/services/media_service.dart';
import 'package:cauce_stream/services/thumbnail_service.dart';
import 'package:cauce_stream/session/session_controller.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/user_service.dart';
import 'package:cauce_stream/session/token_storage.dart';

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

void main() {
  testWidgets('el retroceso del sistema recorre el historial de '
      'pestanas', (tester) async {
    final apiClient = ApiClient(
      baseUrl: 'http://10.15.1.150:8000/api',
      client: MockClient((request) async => http.Response('[]', 200,
          headers: {'content-type': 'application/json'})),
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
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Inicio visible al arrancar.
    expect(find.text('Inicio'), findsWidgets);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

    // Inicio -> Dispositivos -> Biblioteca.
    await tester.tap(find.text('Dispositivos').last);
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    await tester.tap(find.text('Biblioteca').last);
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);

    // Retroceso del sistema: vuelve pestana a pestana.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

    // Con el historial vacio, el retroceso ya no cambia de pestana
    // (deja salir la app por SystemNavigator).
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
  });
}
