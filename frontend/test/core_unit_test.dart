import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/core/network/api_exception.dart';
import 'package:cauce_stream/core/utils/jwt_utils.dart';
import 'package:cauce_stream/controllers/devices_controller.dart';
import 'package:cauce_stream/models/device.dart';
import 'package:cauce_stream/models/user.dart';
import 'package:cauce_stream/services/assignment_service.dart';
import 'package:cauce_stream/services/auth_service.dart';
import 'package:cauce_stream/services/device_service.dart';
import 'package:cauce_stream/widgets/identity_widgets.dart' show CauceStatus;

void main() {
  group('JwtPayload', () {
    test('decodifica un payload valido con sub y exp', () {
      // header.payload.sig — solo importa el payload.
      // {"sub": "3", "exp": 2000000000}
      const token =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIzIiwiZXhwIjoyMDAwMDAwMDAwfQ.abc';
      final payload = decodeJwtPayload(token);

      expect(payload, isNotNull);
      expect(payload!.subject, 3);
      expect(payload.expiresAt, isNotNull);
      expect(payload.isExpired, isFalse);
    });

    test('detecta expiracion', () {
      // {"sub": "1", "exp": 1000000000} (2001: ya vencido).
      const token =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIiwiZXhwIjoxMDAwMDAwMDAwfQ.abc';
      final payload = decodeJwtPayload(token);
      expect(payload, isNotNull);
      expect(payload!.isExpired, isTrue);
    });

    test('rechaza tokens malformados', () {
      expect(decodeJwtPayload('no-es-un-jwt'), isNull);
      expect(decodeJwtPayload('a.b'), isNull);
      expect(decodeJwtPayload('..sig'), isNull);
    });
  });

  group('User.fromJson', () {
    test('parsea el esquema UserRead del backend', () {
      final user = User.fromJson({
        'id': 7,
        'name': 'Elena Salazar',
        'email': 'mediador@cauce.edu',
        'role': {
          'id': 2,
          'name': 'MEDIADOR',
          'description': 'Operador de sala',
        },
        'is_active': true,
        'created_at': '2026-01-15T10:30:00Z',
        'updated_at': '2026-02-01T08:00:00Z',
      });

      expect(user.id, 7);
      expect(user.email, 'mediador@cauce.edu');
      expect(user.role.name, 'MEDIADOR');
      expect(user.isAdmin, isFalse);
      expect(user.isActive, isTrue);
    });

    test('identifica al administrador', () {
      final user = User.fromJson({
        'id': 1,
        'name': 'Admin',
        'email': 'admin@cauce.edu',
        'role': {'id': 1, 'name': 'ADMINISTRADOR', 'description': null},
        'is_active': true,
        'created_at': '2026-01-15T10:30:00Z',
        'updated_at': '2026-02-01T08:00:00Z',
      });
      expect(user.isAdmin, isTrue);
    });
  });

  group('ApiException', () {
    test('clasifica errores de autenticacion', () {
      final e = ApiException(
        kind: ApiErrorKind.auth,
        message: 'Invalid email or password',
        statusCode: 401,
        code: 'not_authenticated',
      );
      expect(e.isAuthError, isTrue);
      expect(e.statusCode, 401);
    });

    test('clasifica errores de red', () {
      final e = ApiException(
        kind: ApiErrorKind.network,
        message: 'No hay conexion',
      );
      expect(e.isAuthError, isFalse);
      expect(e.statusCode, isNull);
    });
  });

  group('ApiClient timeouts', () {
    test('agota la espera y clasifica el error como red', () async {
      final mock = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('{}', 200);
      });
      final client = ApiClient(baseUrl: 'http://10.15.1.150:8000/api', client: mock);

      await expectLater(
        client.post('/auth/login',
            body: const {}, timeout: const Duration(milliseconds: 50)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.network),
        ),
      );
    });

    test('el login usa un timeout mayor que el del cliente', () {
      expect(
        AuthService.loginTimeout,
        greaterThan(ApiClient.defaultTimeout),
        reason: 'bcrypt en el servidor de la sala puede tardar mucho '
            'mas que una peticion normal.',
      );
    });

    test('una respuesta lenta dentro del margen se acepta', () async {
      final mock = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('{"access_token": "a.b.c"}', 200);
      });
      final client = ApiClient(baseUrl: 'http://10.15.1.150:8000/api', client: mock);

      final data = await client.post(
        '/auth/login',
        body: const {'email': 'a@cauce.edu', 'password': '1234'},
        timeout: const Duration(seconds: 5),
      );
      expect(data['access_token'], 'a.b.c');
    });
  });

  group('Device.fromJson y estado', () {
    Map<String, dynamic> deviceJson({
      String status = 'online',
      String? deviceState = 'active',
      String? lastSeen = '2026-10-19T14:00:00Z',
    }) =>
        {
          'id': 1,
          'device_uid': 'totem-central',
          'name': 'Totem Circuito Central',
          'type': 'Totem',
          'ip_address': '10.15.1.170',
          'port': 8080,
          'status': status,
          'device_state': deviceState,
          'current_media': 'mapa_cauca',
          'payload': {'battery_level': 88},
          'last_seen': lastSeen,
          'created_at': '2026-10-07T10:00:00Z',
          'updated_at': '2026-10-19T14:00:00Z',
        };

    test('mapea el esquema DeviceRead completo', () {
      final device = Device.fromJson(deviceJson());
      expect(device.id, 1);
      expect(device.deviceUid, 'totem-central');
      expect(device.type, 'Totem');
      expect(device.ipAddress, '10.15.1.170');
      expect(device.port, 8080);
      expect(device.currentMedia, 'mapa_cauca');
      expect(device.payload, {'battery_level': 88});
      expect(device.lastSeen, isNotNull);
    });

    test('combina conectividad y estado operativo', () {
      expect(Device.fromJson(deviceJson()).cauceStatus,
          CauceStatus.active);
      expect(Device.fromJson(deviceJson()).statusLabel, 'Activo');

      final idle = Device.fromJson(deviceJson(deviceState: 'idle'));
      expect(idle.cauceStatus, CauceStatus.alert);
      expect(idle.statusLabel, 'En espera');
      expect(idle.isStandby, isTrue);
      expect(idle.isActive, isFalse);

      // device_state nulo con heartbeat confirmado cuenta como activo.
      final unknownState = Device.fromJson(deviceJson(deviceState: null));
      expect(unknownState.cauceStatus, CauceStatus.active);
      expect(unknownState.statusLabel, 'Activo');
      expect(unknownState.isActive, isTrue);
      expect(unknownState.isStandby, isFalse);

      final offline = Device.fromJson(deviceJson(status: 'offline'));
      expect(offline.cauceStatus, CauceStatus.offline);
      expect(offline.statusLabel, 'Desconectado');
      expect(offline.isOnline, isFalse);
      expect(offline.isActive, isFalse);
      expect(offline.isStandby, isFalse);
    });

    test('un dispositivo nunca comunicado tiene lastSeen nulo', () {
      final device = Device.fromJson(deviceJson(lastSeen: null));
      expect(device.lastSeen, isNull);
      expect(device.relativeLastSeen, isNull);
    });
  });

  group('DevicesController contadores de estado', () {
    test('activos + en espera + desconectados suman el total; online '
        'con device_state nulo cuenta como activo', () async {
      // DevicesController registra un observador de ciclo de vida.
      TestWidgetsFlutterBinding.ensureInitialized();
      Map<String, dynamic> jsonDevice(
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
            'ws_connected': false,
            'created_at': '2026-10-20T10:00:00',
            'updated_at': '2026-10-27T10:00:00',
          };
      final api = ApiClient(
        baseUrl: 'http://server:8000/api',
        client: MockClient((request) async {
          if (request.url.path == '/api/devices') {
            return http.Response(
              jsonEncode([
                jsonDevice(1, 'tv-activa', 'online', 'active'),
                jsonDevice(2, 'tv-sin-estado', 'online', null),
                jsonDevice(3, 'tv-espera', 'online', 'idle'),
                jsonDevice(4, 'tv-caida', 'offline', null),
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
        }),
      );
      final controller = DevicesController(
        service: DeviceService(client: api),
        assignmentService: AssignmentService(client: api),
      );
      await controller.refresh();

      expect(controller.activeCount, 2);
      expect(controller.standbyCount, 1);
      expect(controller.offlineCount, 1);
      expect(controller.onlineCount, 3);
      expect(
        controller.activeCount +
            controller.standbyCount +
            controller.offlineCount,
        controller.devices.length,
      );
    });
  });

  group('DeviceService rutas', () {
    test('getDevice codifica el uid con espacios en la URL', () async {
      final requests = <http.Request>[];
      final mock = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'id': 1,
            'device_uid': 'SALA PANTALLA 1',
            'name': 'SALA PANTALLA 1',
            'type': 'Pantalla',
            'ip_address': '10.15.1.42',
            'port': null,
            'status': 'online',
            'device_state': 'idle',
            'current_media': null,
            'payload': null,
            'last_seen': '2026-10-19T14:00:00Z',
            'created_at': '2026-10-19T14:00:00Z',
            'updated_at': '2026-10-19T14:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = DeviceService(
        client: ApiClient(
          baseUrl: 'http://10.15.1.150:8000/api',
          client: mock,
        ),
      );

      final device = await service.getDevice('SALA PANTALLA 1');

      expect(requests, hasLength(1));
      // El uid viaja codificado para la URL, sin normalizarse.
      expect(requests.single.url.path, '/api/devices/SALA%20PANTALLA%201');
      // El modelo conserva el uid original.
      expect(device.deviceUid, 'SALA PANTALLA 1');
      expect(device.isOnline, isTrue);
    });
  });
}
