// Indicador LAN: sondeo del endpoint de salud del servidor Cauce
// (GET /api/health -> {"status": "ok"}). Cubre los casos exigidos:
// servidor respondiendo, servidor detenido, timeout de red, uso de
// la direccion local mientras Tailscale este vacia, UI no bloqueada
// durante la comprobacion y recuperacion automatica.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/connectivity_controller.dart';
import 'package:cauce_stream/core/config/api_config.dart';
import 'package:cauce_stream/services/connectivity_service.dart';
import 'package:cauce_stream/widgets/identity_widgets.dart';

void main() {
  group('ConnectivityService', () {
    test('considera activa solo la respuesta del contrato de salud',
        () async {
      final requests = <Uri>[];
      final service = ConnectivityService(
        client: MockClient((request) async {
          requests.add(request.url);
          return http.Response('{"status": "ok"}', 200,
              headers: {'content-type': 'application/json'});
        }),
        serverUrl: 'http://10.15.1.150:8000',
      );
      expect(await service.check(), isTrue);
      expect(
        requests.single.toString(),
        'http://10.15.1.150:8000/api/health',
      );
    });

    test('cuerpo invalido o status distinto no cuentan como LAN activa',
        () async {
      final service = ConnectivityService(
        client: MockClient((request) async => http.Response('{"status": "no"}', 200)),
        serverUrl: 'http://10.15.1.150:8000',
      );
      expect(await service.check(), isFalse);

      final errorStatus = ConnectivityService(
        client: MockClient((request) async => http.Response('boom', 500)),
        serverUrl: 'http://10.15.1.150:8000',
      );
      expect(await errorStatus.check(), isFalse);
    });

    test('servidor detenido (socket) reporta LAN inactiva', () async {
      final service = ConnectivityService(
        client: MockClient((request) async {
          throw const SocketException('connection refused');
        }),
        serverUrl: 'http://10.15.1.150:8000',
      );
      expect(await service.check(), isFalse);
    });

    test('timeout de red reporta LAN inactiva', () async {
      final service = ConnectivityService(
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return http.Response('{"status": "ok"}', 200);
        }),
        serverUrl: 'http://10.15.1.150:8000',
        timeout: const Duration(milliseconds: 20),
      );
      final sw = Stopwatch()..start();
      expect(await service.check(), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('ApiConfig', () {
    test('sin Tailscale configurada se usa unicamente la direccion local',
        () {
      expect(ApiConfig.serverTailscaleUrl, isEmpty);
      expect(ApiConfig.activeServerUrl, ApiConfig.serverLocalUrl);
      expect(ApiConfig.apiBaseUrl, '${ApiConfig.serverLocalUrl}/api');
    });
  });

  group('ConnectivityController y badge', () {
    const okBody = '{"status": "ok"}';

    testWidgets('el backend responde: badge Servidor Activo', (tester) async {
      final controller = ConnectivityController(
        service: ConnectivityService(
          client: MockClient((request) async =>
              http.Response(okBody, 200)),
        ),
        interval: const Duration(milliseconds: 40),
      );
      await _pumpBadge(tester, controller);
      expect(find.text('Servidor\nActivo'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('el backend esta detenido: badge Servidor Inactivo y '
        'recuperacion automatica al volver', (tester) async {
      var up = false;
      final controller = ConnectivityController(
        service: ConnectivityService(
          client: MockClient((request) async {
            if (!up) {
              throw const SocketException('connection refused');
            }
            return http.Response(okBody, 200);
          }),
        ),
        interval: const Duration(milliseconds: 40),
      );
      await _pumpBadge(tester, controller);
      expect(find.text('Servidor\nInactivo'), findsOneWidget);

      // La red vuelve: el sondeo periodico recupera el estado sin
      // recargar nada.
      up = true;
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Servidor\nActivo'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('estado neutro mientras comprueba: la interfaz sigue '
        'respondiendo', (tester) async {
      // Comprobacion colgada: el badge muestra el estado neutro
      // mientras tanto y los frames siguen construyendose.
      final response = Completer<http.Response>();
      final controller = ConnectivityController(
        service: ConnectivityService(
          client: MockClient((request) => response.future),
          timeout: const Duration(seconds: 2),
        ),
        interval: const Duration(seconds: 5),
      );
      await _pumpBadge(tester, controller);
      expect(find.text('Comprobando'), findsOneWidget);

      // El servidor termina de responder: el badge pasa a activa sin
      // ninguna intervencion del usuario.
      response.complete(http.Response(okBody, 200));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Servidor\nActivo'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('el estado solo notifica cuando cambia', (tester) async {
      final controller = ConnectivityController(
        service: ConnectivityService(
          client: MockClient((request) async =>
              http.Response(okBody, 200)),
        ),
        interval: const Duration(milliseconds: 20),
      );
      await tester.pumpWidget(const SizedBox());
      // La comprobacion inicial completa el estado.
      await tester.pump(const Duration(milliseconds: 50));
      var notifications = 0;
      controller.addListener(() => notifications++);
      final before = notifications;
      await tester.pump(const Duration(milliseconds: 100));
      expect(notifications, before);
      expect(controller.status, LanStatus.active);
      controller.dispose();
    });
  });
}

/// Bombea el badge y deja correr la comprobacion inicial del
/// controlador. Nunca usa pumpAndSettle: el punto del badge pulsa
/// con una animacion perpetua.
Future<void> _pumpBadge(
    WidgetTester tester, ConnectivityController controller) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: LanBadge(compact: true)),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 120));
}
