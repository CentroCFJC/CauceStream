// Pruebas del endpoint TEMPORAL de encendido/apagado maestro de la
// sala (ver backend/docs/room_power_temporal.md): parseo de modelos,
// RoomService con http.Client falso (202 / 502 / 403 / red), logica
// del RoomController y Control Maestro en la pestana Dispositivos.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/devices_controller.dart';
import 'package:cauce_stream/controllers/media_library_controller.dart';
import 'package:cauce_stream/controllers/room_controller.dart';
import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/core/network/api_exception.dart';
import 'package:cauce_stream/models/room_power.dart';
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

Map<String, dynamic> taskJson({
  String taskName = 'Cauce_ON',
  String? lastRunTime = '2026-10-26T08:30:00',
  int? lastTaskResult = 0,
  bool running = false,
  bool? succeeded = true,
}) => {
  'task_name': taskName,
  'last_run_time': lastRunTime,
  'last_task_result': lastTaskResult,
  'running': running,
  'succeeded': succeeded,
};

Map<String, dynamic> statusJson({
  Map<String, dynamic>? on,
  Map<String, dynamic>? off,
}) => {
  'on': on ?? taskJson(),
  'off': off ??
      taskJson(
        taskName: 'Cauce_OFF',
        lastRunTime: null,
        lastTaskResult: null,
        succeeded: null,
      ),
};

void main() {
  group('RoomPowerAction', () {
    test('parsea on/off y rechaza cualquier otra cosa', () {
      expect(RoomPowerAction.parse('on'), RoomPowerAction.on);
      expect(RoomPowerAction.parse('off'), RoomPowerAction.off);
      expect(RoomPowerAction.on.wireName, 'on');
      expect(
        () => RoomPowerAction.parse('reboot'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RoomPowerAccepted / RoomPowerStatus (fromJson)', () {
    test('mapea el 202 del POST', () {
      final accepted = RoomPowerAccepted.fromJson({
        'action': 'on',
        'task_name': 'Cauce_ON',
      });
      expect(accepted.action, RoomPowerAction.on);
      expect(accepted.taskName, 'Cauce_ON');
    });

    test('valida la accion de la respuesta', () {
      expect(
        () => RoomPowerAccepted.fromJson({
          'action': 'restart',
          'task_name': 'Cauce_ON',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('mapea el GET: tareas corridas y nunca corridas', () {
      final status = RoomPowerStatus.fromJson(statusJson());
      expect(status.on.taskName, 'Cauce_ON');
      expect(status.on.lastRunTime, DateTime.parse('2026-10-26T08:30:00'));
      expect(status.on.lastTaskResult, 0);
      expect(status.on.running, isFalse);
      expect(status.on.succeeded, isTrue);
      expect(status.on.resultLabel, 'Ultima ejecucion exitosa');

      expect(status.off.taskName, 'Cauce_OFF');
      expect(status.off.lastRunTime, isNull);
      expect(status.off.lastTaskResult, isNull);
      expect(status.off.succeeded, isNull);
      expect(status.off.resultLabel, 'Nunca ha corrido');

      expect(status.taskFor(RoomPowerAction.on), same(status.on));
      expect(status.taskFor(RoomPowerAction.off), same(status.off));
    });

    test('etiquetas de tarea en curso y fallida', () {
      expect(
        RoomTaskStatus.fromJson(taskJson(running: true)).resultLabel,
        'Ejecutandose ahora',
      );
      expect(
        RoomTaskStatus.fromJson(
          taskJson(succeeded: false, lastTaskResult: 1),
        ).resultLabel,
        'Ultima ejecucion fallida (codigo 1)',
      );
    });
  });

  group('RoomService', () {
    test('setPower envia el contrato del POST /room/power', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'action': 'on', 'task_name': 'Cauce_ON'}),
          202,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = _service(client);

      final accepted = await service.setPower(RoomPowerAction.on);

      expect(accepted.action, RoomPowerAction.on);
      expect(accepted.taskName, 'Cauce_ON');
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/room/power');
      expect(jsonDecode(captured!.body), {'action': 'on'});
    });

    test('getStatus mapea el 200 con ambas tareas', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode(statusJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = _service(client);

      final status = await service.getStatus();

      expect(requested!.path, '/api/room/power');
      expect(status.on.succeeded, isTrue);
      expect(status.off.succeeded, isNull);
    });

    test('un 502 host_command_failed se expone como ApiException', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': 'host_command_failed',
            'detail': 'PowerShell no disponible en el servidor.',
          }),
          502,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = _service(client);

      await expectLater(
        service.setPower(RoomPowerAction.off),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.code, 'code', 'host_command_failed')
              .having((e) => e.kind, 'kind', ApiErrorKind.server)
              .having(
                (e) => e.message,
                'message',
                'PowerShell no disponible en el servidor.',
              ),
        ),
      );
    });

    test('un 403 sin devices.control se expone como error de auth', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': 'missing_permission',
            'detail': 'Sin permiso devices.control.',
          }),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = _service(client);

      final exception = await _capture(
        () => service.setPower(RoomPowerAction.on),
      );

      expect(exception, isA<ApiException>());
      final api = exception as ApiException;
      expect(api.isAuthError, isTrue);
      expect(api.statusCode, 403);
    });

    test('sin conexion con el servidor se clasifica como red', () async {
      final client = MockClient((request) async {
        throw http.ClientException('servidor caido');
      });
      final service = _service(client);

      final exception = await _capture(
        () => service.setPower(RoomPowerAction.on),
      );

      expect(exception, isA<ApiException>());
      expect((exception as ApiException).kind, ApiErrorKind.network);
    });
  });

  group('RoomController', () {
    test('202: fase aceptado, mensaje de orden enviada y estado '
        'refrescado con el GET', () async {
      var getStatusCalls = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'action': 'on', 'task_name': 'Cauce_ON'}),
            202,
            headers: {'content-type': 'application/json'},
          );
        }
        getStatusCalls++;
        return http.Response(
          jsonEncode(statusJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = _controller(client);

      await controller.setPower(RoomPowerAction.on);

      expect(controller.phase, RoomPowerPhase.accepted);
      expect(controller.lastAction, RoomPowerAction.on);
      // El 202 nunca se presenta como "sala encendida".
      expect(controller.message, contains('Orden enviada'));
      expect(controller.message, contains('Cauce_ON'));
      expect(controller.message, contains('tard'));
      expect(getStatusCalls, 1);
      expect(controller.status?.on.succeeded, isTrue);
    });

    test('502 host_command_failed: fase error con mensaje de servidor '
        'caido y reintento manual', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': 'host_command_failed',
            'detail': 'No se pudo lanzar la tarea programada.',
          }),
          502,
          headers: {'content-type': 'application/json'},
        ),
      );
      final controller = _controller(client);

      await controller.setPower(RoomPowerAction.off);

      expect(controller.phase, RoomPowerPhase.error);
      expect(controller.message, contains('no pudo lanzar la tarea'));
      expect(controller.message, contains('Verifica el servidor'));
      expect(controller.message, contains('reintenta'));
    });

    test('403: mensaje de permisos, sin lanzar', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'code': 'missing_permission', 'detail': '403'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );
      final controller = _controller(client);

      await controller.setPower(RoomPowerAction.on);

      expect(controller.phase, RoomPowerPhase.error);
      expect(controller.message, 'No tienes permiso para controlar la sala.');
    });

    test('refreshStatus conserva el ultimo estado conocido en fallo', () async {
      var failStatus = false;
      final client = MockClient((request) async {
        if (failStatus) throw http.ClientException('servidor caido');
        return http.Response(
          jsonEncode(statusJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = _controller(client);

      await controller.refreshStatus();
      final before = controller.status;
      expect(before, isNotNull);

      failStatus = true;
      await controller.refreshStatus();

      expect(controller.status, same(before));
    });

    test(
      'un envio en curso bloquea una segunda orden (sin doble POST)',
      () async {
        var posts = 0;
        var getStatusCalls = 0;
        final client = MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            return http.Response(
              jsonEncode({'action': 'on', 'task_name': 'Cauce_ON'}),
              202,
              headers: {'content-type': 'application/json'},
            );
          }
          getStatusCalls++;
          return http.Response(
            jsonEncode(statusJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final controller = _controller(client);

        final first = controller.setPower(RoomPowerAction.on);
        final second = controller.setPower(RoomPowerAction.on);
        await Future.wait([first, second]);

        expect(posts, 1);
        expect(getStatusCalls, 1);
      },
    );

    test('mientras una tarea corre, se sondea el GET hasta que termina',
        () {
      fakeAsync((async) {
        var getStatusCalls = 0;
        final client = MockClient((request) async {
          getStatusCalls++;
          final running = getStatusCalls == 1;
          return http.Response(
            jsonEncode(
              statusJson(
                on: running
                    ? taskJson(
                        running: true,
                        lastTaskResult: 267009,
                        succeeded: false,
                      )
                    : taskJson(),
              ),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final controller = _controller(client);

        // Primer GET: la tarea Cauce_ON esta corriendo.
        controller.refreshStatus();
        async.elapse(const Duration(milliseconds: 10));
        expect(getStatusCalls, 1);
        expect(controller.status?.on.running, isTrue);

        // El sondeo refresca solo (5s) y ve la tarea terminada.
        async.elapse(const Duration(seconds: 5));
        expect(getStatusCalls, 2);
        expect(controller.status?.on.running, isFalse);

        // Terminada la tarea, el sondeo se detiene.
        async.elapse(const Duration(seconds: 30));
        expect(getStatusCalls, 2);

        controller.dispose();
      });
    });
  });

  group('Control Maestro (DevicesScreen)', () {
    testWidgets('con devices.control se muestra; el flujo pide '
        'confirmacion, envia el POST y refleja el estado del GET', (
      tester,
    ) async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && request.url.path == '/api/room/power') {
          return http.Response(
            jsonEncode({'action': 'on', 'task_name': 'Cauce_ON'}),
            202,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/room/power') {
          return http.Response(
            jsonEncode(statusJson()),
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
      await _pumpDevicesScreen(
        tester,
        client,
        session: _AdminSession(apiClient: _apiClient(client)),
      );

      // El Control Maestro nace cerrado: las acciones solo aparecen
      // al expandir la tarjeta (AnimatedCrossFade conserva el hijo
      // oculto en el arbol, por eso se comprueba lo golpeable).
      expect(find.text('Encender Sala').hitTestable(), findsNothing);
      await tester.tap(find.text('Control Maestro de Sala'));
      // Sin pumpAndSettle (el punto pulsante de estado repite para
      // siempre, igual que en shell_test) y con varios frames: el
      // AnimatedSize del desplegable avanza frame a frame.
      await _pumpFrames(tester);

      expect(find.text('Encender Sala').hitTestable(), findsOneWidget);
      expect(find.text('Apagar Sala').hitTestable(), findsOneWidget);

      // Confirmacion: es la sala completa, no un dispositivo.
      await tester.tap(find.text('Encender Sala'));
      await _pumpFrames(tester);
      expect(find.text('ENCENDER SALA'), findsOneWidget);
      expect(find.text('Encender sala'), findsOneWidget);

      await tester.tap(find.text('Encender sala'));
      await tester.pump();
      await _pumpFrames(tester);

      // 202 = orden enviada (tarea disparada), nunca "sala encendida".
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Orden enviada'), findsOneWidget);
      expect(find.textContaining('sala encendida'), findsNothing);

      final post = requests
          .where((r) => r.method == 'POST' && r.url.path == '/api/room/power')
          .single;
      expect(jsonDecode(post.body), {'action': 'on'});
      expect(
        requests.any(
          (r) => r.method == 'GET' && r.url.path == '/api/room/power',
        ),
        isTrue,
      );

      // Tras el GET, los botones muestran la ultima ejecucion de su
      // tarea (succeeded == true para Cauce_ON; nunca corrida para
      // Cauce_OFF).
      expect(find.text('Ultima ejecucion exitosa'), findsOneWidget);
      expect(find.text('Nunca ha corrido'), findsOneWidget);
    });

    testWidgets('sin devices.control la tarjeta maestra no se muestra', (
      tester,
    ) async {
      final client = MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      // Sesion sin usuario cargado: equivalente a un mediador
      // (isAdmin false, sin `devices.control`).
      await _pumpDevicesScreen(
        tester,
        client,
        session: _MediatorSession(apiClient: _apiClient(client)),
      );

      expect(find.text('Control Maestro de Sala'), findsNothing);
      expect(find.text('Encender Sala'), findsNothing);
    });
  });
}

RoomService _service(http.Client client) {
  final apiClient = _apiClient(client);
  return RoomService(client: apiClient);
}

/// Avanza el reloj frame a frame: el desplegable del Control Maestro
/// (AnimatedCrossFade + AnimatedSize) y la hoja de confirmacion
/// progresan con cada frame, no con un unico salto temporal.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

RoomController _controller(http.Client client) =>
    RoomController(service: _service(client));

ApiClient _apiClient(http.Client client) =>
    ApiClient(baseUrl: 'http://10.15.1.150:8000/api', client: client);

Future<Object?> _capture(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (e) {
    return e;
  }
}

class _DevicesHarness {
  _DevicesHarness({required this.session, required this.room});
  final _FakeSession session;
  final RoomController room;
}

Future<_DevicesHarness> _pumpDevicesScreen(
  WidgetTester tester,
  http.Client client, {
  required _FakeSession session,
}) async {
  final apiClient = _apiClient(client);
  final devices = DevicesController(
    service: DeviceService(client: apiClient),
    assignmentService: AssignmentService(client: apiClient),
  );
  final mediaService = MediaService(client: apiClient);
  final mediaLibrary = MediaLibraryController(
    service: mediaService,
    thumbnails: ThumbnailService(
      service: mediaService,
      cacheDirectory: _tempDir(),
    ),
  );
  final room = RoomController(service: RoomService(client: apiClient));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        // El tipo explícito importa: las sesiones falsas son
        // subclases de SessionController y la UI lo consulta por el
        // tipo base.
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider.value(value: devices),
        ChangeNotifierProvider.value(value: mediaLibrary),
        ChangeNotifierProvider.value(value: room),
      ],
      child: const MaterialApp(home: Scaffold(body: DevicesScreen())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  return _DevicesHarness(session: session, room: room);
}

Directory _tempDir() => Directory.systemTemp.createTempSync('cauce_room_test');

/// Sesion falsa: la capacidad `devices.control` se deriva del rol,
/// igual que el resto de capacidades del frontend.
abstract class _FakeSession extends SessionController {
  _FakeSession({required ApiClient apiClient})
    : super(
        storage: _FakeStorage(),
        authService: AuthService(client: apiClient),
        userService: UserService(client: apiClient),
        apiClient: apiClient,
      );
}

class _AdminSession extends _FakeSession {
  _AdminSession({required super.apiClient});

  @override
  bool get isAdmin => true;
}

class _MediatorSession extends _FakeSession {
  _MediatorSession({required super.apiClient});

  @override
  bool get isAdmin => false;
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
