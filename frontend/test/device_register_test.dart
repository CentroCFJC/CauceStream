// Pruebas del flujo de registro de dispositivos con autodescubrimiento:
// activacion, sondeo periodico, seleccion, edicion de IP, registro
// (sin puerto), desactivacion y errores.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cauce_stream/controllers/devices_controller.dart';
import 'package:cauce_stream/core/network/api_client.dart';
import 'package:cauce_stream/screens/devices/device_register_screen.dart';
import 'package:cauce_stream/services/device_service.dart';

const _baseUrl = 'http://10.15.1.150:8000/api';

Map<String, dynamic> _pendingJson(
        String uid, String ip, [String? state]) =>
    {
      'device_uid': uid,
      'ip_address': ip,
      'device_state': ?state,
    };

Map<String, dynamic> _deviceReadJson(String uid) => {
      'id': 9,
      'device_uid': uid,
      'name': uid,
      'type': 'Totem',
      'ip_address': '10.15.1.170',
      'port': null,
      'status': 'offline',
      'device_state': null,
      'current_media': null,
      'payload': null,
      'last_seen': null,
      'created_at': '2026-10-19T14:00:00Z',
      'updated_at': '2026-10-19T14:00:00Z',
    };

/// Backend simulado que registra cada peticion recibida.
class _Backend {
  _Backend({
    List<Map<String, dynamic>> Function()? pendingGetter,
    this.autoconfigDelay,
  }) : pendingGetter = pendingGetter ?? (() => const <Map<String, dynamic>>[]);

  final List<http.Request> requests = [];
  final List<Map<String, dynamic>> Function() pendingGetter;

  /// Retraso de la activacion para observar el estado "activando".
  Duration? autoconfigDelay;
  bool autoconfigFails = false;
  int registerStatusCode = 201;
  String registerDetail = 'El identificador ya esta registrado.';

  int count(String method, String path) => requests
      .where((r) => r.method == method && r.url.path == path)
      .length;

  http.Request? lastOf(String method, String path) {
    for (final r in requests.reversed) {
      if (r.method == method && r.url.path == path) return r;
    }
    return null;
  }

  http.Client get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'POST' && path == '/api/devices/autoconfig') {
          // El retraso solo afecta a la activacion, no a la
          // desactivacion que ocurre al cerrar la pantalla.
          final enabled =
              (jsonDecode(request.body) as Map<String, dynamic>)['enabled']
                  as bool? ??
              false;
          if (enabled && autoconfigDelay != null) {
            await Future<void>.delayed(autoconfigDelay!);
          }
          if (autoconfigFails) {
            throw http.ClientException('servidor caido');
          }
          return http.Response('{"enabled": true}', 200);
        }
        if (request.method == 'GET' &&
            path == '/api/devices/autoconfig/pending') {
          return http.Response(jsonEncode(pendingGetter()), 200,
              headers: {'content-type': 'application/json'});
        }
        if (request.method == 'POST' && path == '/api/devices') {
          if (registerStatusCode != 201) {
            return http.Response(
              jsonEncode({
                'code': 'device_exists',
                'detail': registerDetail,
              }),
              registerStatusCode,
              headers: {'content-type': 'application/json'},
            );
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_deviceReadJson(body['device_uid'])),
              201,
              headers: {'content-type': 'application/json'});
        }
        if (request.method == 'GET' && path == '/api/devices') {
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      });
}

/// Monta la pantalla sobre una raiz desde la que se puede abrir y
/// cerrar, con el controlador de inventario inyectado.
Future<DevicesController> _pumpApp(
    WidgetTester tester, http.Client client) async {
  final apiClient = ApiClient(baseUrl: _baseUrl, client: client);
  final devices = DevicesController(
    service: DeviceService(client: apiClient),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<DevicesController>.value(
      value: devices,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeviceRegisterScreen(),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return devices;
}

Future<void> _openScreen(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Desmonta el arbol para que dispose cancele temporizadores y lance
/// la desactivacion del autodescubrimiento.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// El boton de guardar puede quedar bajo el borde del viewport: se
/// desplaza hasta el antes de pulsarlo.
Future<void> _tapSave(WidgetTester tester) async {
  final save = find.text('Guardar dispositivo');
  await tester.ensureVisible(save);
  await tester.pump();
  await tester.tap(save);
}

/// Bombea tiempo falso suficiente para que el registro asincrono
/// complete y la ruta termine su animacion de salida. No se usa
/// pumpAndSettle: los encabezados tienen animaciones infinitas.
Future<void> _flushRegistration(WidgetTester tester) async {
  for (final d in [
    const Duration(milliseconds: 100),
    const Duration(milliseconds: 100),
    const Duration(seconds: 1),
  ]) {
    await tester.pump(d);
  }
}

void main() {
  testWidgets(
      'activa el autodescubrimiento al abrir y lo desactiva al salir',
      (tester) async {
    final backend = _Backend();
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    final enable =
        backend.lastOf('POST', '/api/devices/autoconfig');
    expect(enable, isNotNull);
    expect(jsonDecode(enable!.body), {'enabled': true});

    await _unmount(tester);

    final disable =
        backend.lastOf('POST', '/api/devices/autoconfig');
    expect(disable, isNotNull);
    expect(disable!.body, isNot(enable.body));
    expect(jsonDecode(disable.body), {'enabled': false});
  });

  testWidgets('muestra el estado de activacion y luego la busqueda',
      (tester) async {
    final backend = _Backend(autoconfigDelay: const Duration(seconds: 1));
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);

    // La activacion sigue pendiente: estado "activando".
    expect(find.text('Activando autodescubrimiento...'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Buscando dispositivos...'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets(
      'sondea los pendientes cada 3 segundos y muestra los detectados',
      (tester) async {
    final backend = _Backend(
      pendingGetter: () => [
        _pendingJson('totem-central', '10.15.1.170', 'active'),
        _pendingJson('casco-vr-02', '10.15.1.112'),
      ],
    );
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    // Primer sondeo inmediato tras activar.
    expect(find.text('totem-central'), findsOneWidget);
    expect(find.text('IP: 10.15.1.170'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('casco-vr-02'), findsOneWidget);
    expect(backend.count('GET', '/api/devices/autoconfig/pending'), 1);

    // El temporizador vuelve a consultar a los 3 segundos.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.count('GET', '/api/devices/autoconfig/pending'), 2);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(backend.count('GET', '/api/devices/autoconfig/pending'), 3);

    await _unmount(tester);
  });

  testWidgets('seleccion llena la IP, que sigue siendo editable',
      (tester) async {
    final backend = _Backend(
      pendingGetter: () => [_pendingJson('totem-central', '10.15.1.170')],
    );
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('totem-central'));
    await tester.pump();

    Finder ipField() => find.widgetWithIcon(TextField, Icons.dns);
    expect(
      tester.widget<TextField>(ipField()).controller!.text,
      '10.15.1.170',
    );

    // Correccion manual de la IP.
    await tester.enterText(ipField(), '10.15.1.199');
    await tester.pump();
    expect(
      tester.widget<TextField>(ipField()).controller!.text,
      '10.15.1.199',
    );

    await _unmount(tester);
  });

  testWidgets(
      'registra con device_uid e IP confirmada, sin puerto, y cierra',
      (tester) async {
    final backend = _Backend(
      pendingGetter: () => [_pendingJson('totem-central', '10.15.1.170')],
    );
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('totem-central'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithIcon(TextField, Icons.dns), '10.15.1.199');
    await tester.pump();

    await _tapSave(tester);
    await _flushRegistration(tester);

    final register = backend.lastOf('POST', '/api/devices');
    expect(register, isNotNull);
    final body = jsonDecode(register!.body) as Map<String, dynamic>;
    expect(body['device_uid'], 'totem-central');
    expect(body['name'], 'totem-central');
    expect(body['type'], 'otro'); // type canonico del backend
    expect(body['ip_address'], '10.15.1.199');
    // El contrato del registro ya no incluye el puerto.
    expect(body.containsKey('port'), isFalse);

    // La pantalla se cerro y el inventario compartido se refresco.
    expect(find.byType(DeviceRegisterScreen), findsNothing);
    expect(backend.count('GET', '/api/devices'), greaterThanOrEqualTo(1));

    // Al salir se desactivo el autodescubrimiento.
    final disable = backend.lastOf('POST', '/api/devices/autoconfig');
    expect(jsonDecode(disable!.body), {'enabled': false});

    await _unmount(tester);
  });

  testWidgets('un fallo de registro conserva los datos y muestra el error',
      (tester) async {
    final backend = _Backend(
      pendingGetter: () => [_pendingJson('totem-central', '10.15.1.170')],
    )
      ..registerStatusCode = 409
      ..registerDetail = 'El identificador ya esta registrado.';
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('totem-central'));
    await tester.pump();
    await _tapSave(tester);
    await _flushRegistration(tester);

    expect(find.text('El identificador ya esta registrado.'),
        findsOneWidget);
    expect(find.byType(DeviceRegisterScreen), findsOneWidget);
    // Los datos introducidos siguen en el formulario.
    expect(
      tester
          .widget<TextField>(find.widgetWithIcon(TextField, Icons.dns))
          .controller!
          .text,
      '10.15.1.170',
    );

    await _unmount(tester);
  });

  testWidgets(
      'avisa si el equipo seleccionado desaparece y bloquea el registro',
      (tester) async {
    var pollCalls = 0;
    final backend = _Backend(
      pendingGetter: () => pollCalls++ == 0
          ? [_pendingJson('totem-central', '10.15.1.170')]
          : const <Map<String, dynamic>>[],
    );
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('totem-central'));
    await tester.pump();

    // El siguiente sondeo ya no reporta el equipo.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('ya no aparece en la red'), findsWidgets);

    await _tapSave(tester);
    await _flushRegistration(tester);

    expect(find.textContaining('Vuelve a buscarlo'), findsWidgets);
    expect(backend.count('POST', '/api/devices'), 0);

    await _unmount(tester);
  });

  testWidgets('un error de activacion ofrece reintento y se recupera',
      (tester) async {
    final backend = _Backend(
      pendingGetter: () => [_pendingJson('totem-central', '10.15.1.170')],
    )
      ..autoconfigFails = true;
    await _pumpApp(tester, backend.client);
    await _openScreen(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('totem-central'), findsNothing);

    // El reintento activa y sondea con exito.
    backend.autoconfigFails = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('totem-central'), findsOneWidget);

    await _unmount(tester);
  });
}
