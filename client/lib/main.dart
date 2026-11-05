import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/constants.dart';
import 'screens/auto_playback_screen.dart';
import 'services/cauce_heartbeat_service.dart';
import 'services/device_identity.dart';
import 'services/playback_socket_service.dart';
import 'services/playback_state.dart';
import 'services/power_executor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final playbackService = await _startDeviceServices();
  runApp(CauceStreamApp(playbackService: playbackService));
}

/// Arranca los servicios globales del protocolo de dispositivos:
/// heartbeat HTTP (conectividad + `current_media`) y WebSocket de
/// playback (asignación vigente). Ambos comparten el [PlaybackState]
/// del medio confirmado en pantalla. Son globales a la app: viven
/// mientras esté abierta, sin importar la navegación.
Future<PlaybackSocketService?> _startDeviceServices() async {
  final deviceUid = await DeviceIdentity.resolve();
  debugPrint('[CAUCE] device_uid resuelto: "$deviceUid"');

  final serverUrl = AppConfig.cauceServerUrl;
  if (serverUrl == null) {
    debugPrint(
      '[CAUCE] CAUCE_SERVER_URL no está definida: heartbeats y WS '
      'deshabilitados',
    );
    return null;
  }
  if (deviceUid.isEmpty) {
    debugPrint(
      '[CAUCE] No se pudo resolver el nombre del dispositivo: '
      'heartbeats y WS deshabilitados',
    );
    return null;
  }

  final deviceKey = AppConfig.deviceSecret;
  final playbackState = PlaybackState();

  // Diagnóstico de energía al arranque (NO bloqueante: un canal lento o
  // ausente jamás debe retrasar el heartbeat ni el WebSocket).
  final powerExecutor = const MethodChannelPowerExecutor();
  unawaited(_logPowerCapabilities(powerExecutor));

  // El heartbeat NO lo sustituye el WS: sigue reportando conectividad
  // y el medio realmente en reproducción.
  CauceHeartbeatService(
    baseUrl: serverUrl,
    deviceUid: deviceUid,
    deviceKey: deviceKey,
    playbackState: playbackState,
  ).start();

  final playbackService = PlaybackSocketService(
    baseUrl: serverUrl,
    deviceUid: deviceUid,
    deviceKey: deviceKey,
    playbackState: playbackState,
    powerExecutor: powerExecutor,
  )..start();
  return playbackService;
}

/// Loguea las capacidades de energía del dispositivo (si el box está
/// aprovisionado como Device Owner/Admin y puede apagar pantalla).
/// Corre en segundo plano: nunca bloquea el arranque de los servicios.
Future<void> _logPowerCapabilities(PowerExecutor executor) async {
  try {
    final caps = await executor.capabilities();
    debugPrint(
      '[CAUCE] Capacidades de energía: wake=${caps.canWake} '
      'standby=${caps.canStandby} device_owner=${caps.deviceOwner} '
      'admin_active=${caps.adminActive}',
    );
    if (!caps.canStandby) {
      debugPrint(
        '[CAUCE] Apagar pantalla NO disponible por la app: aprovisionar '
        'como Device Owner (client/docs/device_owner_setup.md)',
      );
    }
  } catch (e) {
    debugPrint('[CAUCE] No se pudieron consultar las capacidades de energía: $e');
  }
}

class CauceStreamApp extends StatelessWidget {
  const CauceStreamApp({super.key, this.home, this.playbackService});

  final Widget? home;
  final PlaybackSocketService? playbackService;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: MaterialApp(
        title: 'CAUCE Stream',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A1628),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF1565C0),
            surface: Color(0xFF0D1D34),
          ),
          useMaterial3: true,
          focusColor: Colors.white,
        ),
        home:
            home ?? AutoPlaybackScreen(playbackService: playbackService),
      ),
    );
  }
}
