/// Tests del indicador de conectividad del dispositivo del detalle:
/// mapeo de estados reales (heartbeat, canal WS) a la representacion
/// visual (verde/check, ambar/pausa, rojo/X) y flecha del canal de
/// comandos independiente del heartbeat. El estado del servidor no se
/// prueba aqui: vive en la pastilla LAN del encabezado.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cauce_stream/models/device.dart';
import 'package:cauce_stream/widgets/cauce_headers.dart';
import 'package:cauce_stream/widgets/device_connection_status.dart';
import 'package:cauce_stream/widgets/identity_widgets.dart';

Map<String, dynamic> _device({
  String status = 'online',
  String? deviceState,
  bool wsConnected = false,
}) =>
    {
      'id': 1,
      'device_uid': 'totem-sala-1',
      'name': 'Totem Sala 1',
      'type': 'TV',
      'status': status,
      'device_state': deviceState,
      'ws_connected': wsConnected,
      'ip_address': '10.15.1.10',
      'created_at': '2026-10-20T10:00:00',
      'updated_at': '2026-10-27T10:00:00',
    };

Widget _host(Device device) => MaterialApp(
      home: Scaffold(body: DeviceConnectionStatus(device: device)),
    );

void main() {
  testWidgets('dispositivo activo con canal vivo: check verde y canal '
      'activo; el nombre y el icono de tipo van en la pastilla',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(Device.fromJson(
        _device(deviceState: 'active', wsConnected: true),
      )),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Identidad del dispositivo dentro de la pastilla, sin textos de
    // estado: el chulito ya lo representa.
    expect(find.text('Totem Sala 1'), findsOneWidget);
    expect(find.byIcon(Icons.tv), findsOneWidget);
    expect(find.text('Dispositivo'), findsNothing);
    expect(find.text('Activo'), findsNothing);

    expect(find.bySemanticsLabel('Dispositivo Activo'), findsOneWidget);
    expect(find.bySemanticsLabel('Canal de comandos activo'), findsOneWidget);
    // Dos chulitos verdes: el del dispositivo y el del canal en el
    // codo del conector.
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    semantics.dispose();
  });

  testWidgets('standby (device_state idle) se distingue de la '
      'desconexion: ambar con pausa', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(Device.fromJson(_device(deviceState: 'idle'))),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.bySemanticsLabel('Dispositivo En espera'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    // En espera pero en linea: la unica X es la del canal, no la del
    // dispositivo.
    expect(find.byIcon(Icons.close), findsOneWidget);
    // El canal se representa por si mismo, independiente del heartbeat.
    expect(
      find.bySemanticsLabel('Canal de comandos inactivo'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('dispositivo sin heartbeat: rojo con X, sin fingir canal',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(Device.fromJson(_device(status: 'offline', wsConnected: true))),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.bySemanticsLabel('Dispositivo Desconectado'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    // Un dispositivo que todavia tiene canal WS no se muestra como
    // desconectado en la flecha: cada estado es ortogonal.
    expect(find.bySemanticsLabel('Canal de comandos activo'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('nombres largos no desbordan la pastilla en pantallas '
      'pequenas', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(Device.fromJson(
        _device(deviceState: 'active', wsConnected: true),
      ).copyWithName('Sala Interactiva de Realidad Virtual Norte')),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // El texto se acorta con ellipsis, no rompe el layout.
    final text = tester.widget<Text>(find.textContaining('Sala Interactiva'));
    expect(text.overflow ?? TextOverflow.clip, TextOverflow.ellipsis);
  });

  // La flecha vertical del conector debe caer bajo el punto medio de
  // la pastilla LAN del encabezado, con el mismo inset (24) que usa
  // la pantalla de detalle, en cualquier ancho y con nombres largos:
  // la pastilla se acorta, la flecha no se mueve.
  Widget screenWith(Device device) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Titulo corto: la prueba solo necesita la pastilla LAN
              // y el avatar en su posicion real del encabezado.
              const StackHeader(
                title: 'Detalle',
                showLogo: false,
                titleFontSize: 16,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DeviceConnectionStatus(device: device),
              ),
            ],
          ),
        ),
      );

  void expectAlignedToServerBadge(WidgetTester tester) {
    final badge = tester.getRect(find.byType(LanBadge));
    final status = tester.getRect(find.byType(DeviceConnectionStatus));
    final inset = DeviceConnectionStatus.serverBadgeCenterOffset(
      textScaler: TextScaler.noScaling,
    );
    expect(
      status.right - inset,
      moreOrLessEquals(badge.center.dx, epsilon: 2.0),
      reason: 'la flecha vertical debe caer bajo la pastilla del '
          'servidor, no en el centro de la pantalla',
    );
  }

  testWidgets('la flecha vertical queda bajo el centro de la pastilla '
      'del servidor en varios anchos', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in const [
      Size(800, 600),
      Size(1024, 768),
      Size(411, 891),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        screenWith(Device.fromJson(
          _device(deviceState: 'active', wsConnected: true),
        )),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expectAlignedToServerBadge(tester);
    }
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('con nombre largo la pastilla cede ancho y la flecha se '
      'mantiene bajo la pastilla del servidor', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      screenWith(Device.fromJson(
        _device(deviceState: 'active', wsConnected: true),
      ).copyWithName('Sala Interactiva de Realidad Virtual Norte 2')),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expectAlignedToServerBadge(tester);
    // El nombre largo se acorta dentro de la pastilla.
    final text = tester.widget<Text>(find.textContaining('Sala Interactiva'));
    expect(text.overflow ?? TextOverflow.clip, TextOverflow.ellipsis);
    // La pastilla nunca supera la mitad izquierda: el conector se
    // queda con toda la mitad derecha. (Coordenada relativa al
    // borde izquierdo del componente.)
    final status = tester.getRect(find.byType(DeviceConnectionStatus));
    final nameRect = tester.getRect(find.textContaining('Sala Interactiva'));
    final pillRight = nameRect.right + 14 - status.left;
    expect(
      pillRight,
      lessThanOrEqualTo(status.width / 2 + 1),
      reason: 'la pastilla del dispositivo no debe pasar la mitad '
          'izquierda del componente',
    );
  });
}

extension on Device {
  Device copyWithName(String name) => Device(
    id: id,
    deviceUid: deviceUid,
    name: name,
    type: type,
    status: status,
    deviceState: deviceState,
    ipAddress: ipAddress,
    port: port,
    currentMedia: currentMedia,
    payload: payload,
    lastSeen: lastSeen,
    wsConnected: wsConnected,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
