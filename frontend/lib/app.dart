/// Navegacion principal y proteccion de rutas.
///
/// El flujo de sesion:
/// - Sin token guardado -> LoginScreen.
/// - Token valido (no expirado) -> MainShell (Inicio).
/// - Cerrar sesion -> se elimina el token local y se vuelve al login.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/device.dart';
import 'models/media.dart';
import 'navigation/main_shell.dart';
import 'screens/login/login_screen.dart';
import 'screens/media/media_detail_screen.dart';
import 'screens/media/media_register_screen.dart';
import 'screens/devices/device_detail_screen.dart';
import 'screens/devices/device_register_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'session/session_controller.dart';

/// Rutas nombradas de la aplicacion.
abstract final class Routes {
  static const login = '/login';
  static const shell = '/';
  static const profile = '/profile';
  static const deviceDetail = '/devices/detail';
  static const deviceRegister = '/devices/new';
  static const mediaDetail = '/media/detail';
  static const mediaRegister = '/media/new';
}

/// Puerta de entrada: decide entre login y el area autenticada
/// segun el estado restaurado de la sesion.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionController>().restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select((SessionController s) => s.status);

    switch (status) {
      case SessionStatus.initializing:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case SessionStatus.unauthenticated:
        return const LoginScreen();
      case SessionStatus.authenticated:
        // Las rutas de la app (perfil, detalles, registros) viven en
        // un Navigator anidado que el boton/gesto de retroceso del
        // sistema no consulta: por defecto cerraria la app. Aqui se
        // intercepta y se delega al navegador anidado: si hay ruta
        // apilada (detalle, dialogo, sheet) hace pop; si no, el
        // shell decide (pestana anterior o salir).
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _navigatorKey.currentState?.maybePop();
          },
          child: Navigator(
            key: _navigatorKey,
            onGenerateRoute: _generateRoute,
            initialRoute: Routes.shell,
          ),
        );
    }
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.shell:
        return _fade(const MainShell());
      case Routes.profile:
        return _fade(const ProfileScreen());
      case Routes.deviceDetail:
        return _fade(DeviceDetailScreen(device: settings.arguments as Device));
      case Routes.deviceRegister:
        return _fade(const DeviceRegisterScreen());
      case Routes.mediaDetail:
        return _fade(MediaDetailScreen(media: settings.arguments as Media));
      case Routes.mediaRegister:
        return _fade(const MediaRegisterScreen());
      default:
        return _fade(const MainShell());
    }
  }

  PageRouteBuilder _fade(Widget screen) {
    return PageRouteBuilder(
      pageBuilder: (_, _, _) => screen,
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 220),
    );
  }
}
