import 'dart:convert';

import 'package:cauce_stream/services/cauce_heartbeat_service.dart';
import 'package:cauce_stream/services/playback_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response okResponse() => http.Response(
        jsonEncode({
          'device_uid': 'SALA PANTALLA 1',
          'status': 'online',
          'device_state': 'active',
          'current_media': 'unknown',
          'payload': {},
          'last_seen': '2026-10-19T12:00:00Z',
        }),
        200,
      );

  test('envía el body del contrato y codifica la ruta', () async {
    Uri? capturedUri;
    String? contentType;
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedUri = request.url;
      contentType = request.headers['Content-Type'];
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return okResponse();
    });

    final service = CauceHeartbeatService(
      baseUrl: 'http://10.15.1.150:8000',
      deviceUid: 'SALA PANTALLA 1',
      client: client,
      resolveIpAddress: () async => '10.15.1.99',
      resolveMacAddress: () async => '7C:01:3E:7A:7D:52',
    );

    await service.sendHeartbeat();

    expect(capturedUri!.path, '/api/devices/SALA%20PANTALLA%201/heartbeat');
    expect(contentType, 'application/json');
    expect(capturedBody!['ip_address'], '10.15.1.99');
    // La MAC se reporta como campo general (Wake-on-LAN del servidor),
    // normalizada a mayúsculas por DeviceIdentity.
    expect(capturedBody!['mac_address'], '7C:01:3E:7A:7D:52');
    expect(capturedBody!['device_state'], 'active');
    // Sin medio confirmado: `current_media` se omite (el servidor guarda
    // "unknown") y el retirado `current_application` ya no se envía.
    expect(capturedBody!['payload'], isEmpty);
    expect(
      (capturedBody!['payload'] as Map<String, dynamic>)
          .containsKey('current_application'),
      isFalse,
    );
    // El cliente nunca reporta `status`: lo determina el servidor.
    expect(capturedBody!.containsKey('status'), isFalse);
    service.dispose();
  });

  test('sin MAC resuelta no se envía mac_address', () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return okResponse();
    });

    final service = CauceHeartbeatService(
      baseUrl: 'http://10.15.1.150:8000',
      deviceUid: 'SALA PANTALLA 1',
      client: client,
      resolveIpAddress: () async => '10.15.1.99',
      resolveMacAddress: () async => null,
    );

    await service.sendHeartbeat();

    expect(capturedBody!.containsKey('mac_address'), isFalse);
    service.dispose();
  });

  test('reporta payload.current_media cuando hay un medio confirmado',
      () async {
    Map<String, dynamic>? capturedBody;
    final client = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return okResponse();
    });
    final playbackState = PlaybackState()..setPlaying(5);
    final service = CauceHeartbeatService(
      baseUrl: 'http://10.15.1.150:8000',
      deviceUid: 'SALA 1',
      deviceKey: 'secreto',
      playbackState: playbackState,
      client: client,
      resolveIpAddress: () async => '10.15.1.99',
    );

    await service.sendHeartbeat();

    // Media.id entero, no "unknown" ni nombre de archivo/aplicación.
    expect(capturedBody!['payload'], {'current_media': 5});

    playbackState.clear();
    await service.sendHeartbeat();
    expect(capturedBody!['payload'], isEmpty);
    service.dispose();
  });

  test('404 (dispositivo aún no registrado) no lanza', () async {
    final client = MockClient((request) async => http.Response('{}', 404));
    final service = CauceHeartbeatService(
      baseUrl: 'http://server:8000',
      deviceUid: 'GHOST',
      client: client,
      resolveIpAddress: () async => '10.15.1.99',
    );

    await service.sendHeartbeat(); // debe registrarse el 404, no lanzar

    service.dispose();
  });

  test('envía X-Device-Key cuando está configurado', () async {
    String? receivedKey;
    final client = MockClient((request) async {
      receivedKey = request.headers['x-device-key'];
      return okResponse();
    });
    final service = CauceHeartbeatService(
      baseUrl: 'http://server:8000',
      deviceUid: 'SALA 1',
      deviceKey: 'secreto-compartido',
      client: client,
      resolveIpAddress: () async => '10.15.1.99',
    );

    await service.sendHeartbeat();

    expect(receivedKey, 'secreto-compartido');
    service.dispose();
  });

  test('202 (descubrimiento pendiente por autoconfig) no lanza', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'device_uid': 'GHOST',
          'status': 'pending_registration',
          'last_seen': '2026-10-19T12:00:00Z',
        }),
        202,
      ),
    );
    final service = CauceHeartbeatService(
      baseUrl: 'http://server:8000',
      deviceUid: 'GHOST',
      client: client,
      resolveIpAddress: () async => '10.15.1.99',
    );

    await service.sendHeartbeat(); // aceptado como pendiente, no es fallo

    service.dispose();
  });

  test('un 422 detiene el servicio (no reintenta el mismo payload)',
      () {
    fakeAsync((async) {
      final client =
          MockClient((request) async => http.Response('invalid', 422));
      final service = CauceHeartbeatService(
        baseUrl: 'http://server:8000',
        deviceUid: 'SALA 1',
        client: client,
        interval: const Duration(seconds: 10),
        resolveIpAddress: () async => '10.15.1.99',
      );

      service.start();
      expect(service.isRunning, isTrue);

      async.elapse(const Duration(seconds: 12));
      expect(service.isRunning, isFalse);

      service.dispose();
    });
  });

  test('timeout del servidor no lanza y el servicio sigue', () {
    fakeAsync((async) {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return okResponse();
      });
      final service = CauceHeartbeatService(
        baseUrl: 'http://server:8000',
        deviceUid: 'SALA 1',
        client: client,
        interval: const Duration(seconds: 10),
        timeout: const Duration(seconds: 5),
        resolveIpAddress: () async => '10.15.1.99',
      );

      service.start();
      async.elapse(const Duration(seconds: 25));
      expect(service.isRunning, isTrue);

      service.dispose();
    });
  });

  test('device_state refleja el ciclo de vida', () async {
    final states = <String>[];
    final client = MockClient((request) async {
      states.add(
        (jsonDecode(request.body) as Map<String, dynamic>)['device_state']
            as String,
      );
      return okResponse();
    });
    final service = CauceHeartbeatService(
      baseUrl: 'http://server:8000',
      deviceUid: 'SALA 1',
      client: client,
      resolveIpAddress: () async => '10.15.1.99',
    );

    expect(service.deviceState, 'active'); // en primer plano al arrancar

    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await service.sendHeartbeat();
    expect(service.deviceState, 'idle');
    expect(states.last, 'idle'); // un dispositivo idle sigue reportando

    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(service.deviceState, 'active');

    service.dispose();
  });
}
