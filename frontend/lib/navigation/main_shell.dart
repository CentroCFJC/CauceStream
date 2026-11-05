/// Shell principal con la barra de navegacion inferior de 5 entradas
/// (Inicio, Dispositivos, Biblioteca, Actividad, Mas), tal como aparece
/// en las referencias de Stitch. "Mas" abre el perfil, que en las
/// referencias es una pantalla apilada con cierre.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../controllers/devices_controller.dart';
import '../core/theme/cauce_colors.dart';
import '../core/theme/cauce_theme.dart';
import '../screens/activities/activities_screen.dart';
import '../screens/devices/devices_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/media/media_library_screen.dart';
import '../session/session_controller.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  /// Historial de pestanas visitadas: el retroceso del sistema
  /// vuelve a la pestana anterior y solo sale de la app cuando ya no
  /// queda historial.
  final List<int> _tabHistory = [];

  late final DevicesController _devices;

  late final List<Widget> _screens = <Widget>[
    const HomeScreen(),
    const DevicesScreen(),
    const MediaLibraryScreen(),
    const ActivitiesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Referencia capturada aqui: dispose no puede usar context.read
    // sobre un elemento desmontandose.
    _devices = context.read<DevicesController>();
    // Un unico ciclo de sondeo compartido por todas las pestanas.
    _devices.startPolling();
    // La precarga del perfil (rol) puede fallar por red al arrancar;
    // sin rol la app ocultaria acciones de administracion (p. ej. el
    // boton "Nuevo Medio") para siempre. Al entrar al shell se
    // reintenta una vez si aun no se conoce el usuario.
    final session = context.read<SessionController>();
    if (!session.hasUser) {
      unawaited(session.loadProfile());
    }
  }

  @override
  void dispose() {
    // Evita timers huerfanos al cerrar sesion (el shell se desmonta).
    _devices.stopPolling();
    super.dispose();
  }

  void _onTap(int index) {
    if (index == 4) {
      Navigator.of(context).pushNamed(Routes.profile);
      return;
    }
    if (index == _currentIndex) return;
    _tabHistory.add(_currentIndex);
    setState(() => _currentIndex = index);
  }

  /// Retroceso del sistema sobre el shell: pestana anterior o, sin
  /// historial, salida de la app.
  void _handleSystemBack() {
    if (_tabHistory.isNotEmpty) {
      setState(() => _currentIndex = _tabHistory.removeLast());
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
        // Fondo que asoma en la franja superior (bajo la barra de
        // estado) y en la franja inferior (sobre la barra de gestos).
        backgroundColor: CauceColors.peachSurface,
        body: Column(
          children: [
            // El contenido empieza bajo la barra de estado del
            // telefono: los encabezados reservan ese inset por si
            // mismos.
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _screens),
            ),
            // SafeArea inferior: la barra de navegacion queda por
            // encima de la barra de gestos del sistema (el espacio
            // que antes dejaba la franja de version).
            SafeArea(
              top: false,
              child: _CauceNavBar(
                currentIndex: _currentIndex == 4 ? 0 : _currentIndex,
                onTap: _onTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CauceNavBar extends StatelessWidget {
  const _CauceNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home, 'Inicio'),
    (Icons.devices, 'Dispositivos'),
    (Icons.video_library, 'Biblioteca'),
    (Icons.hub, 'Actividad'),
    (Icons.more_horiz, 'Mas'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CauceColors.cream.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF261813).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        height: 76,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++)
                _NavItem(
                  icon: _items[i].$1,
                  label: _items[i].$2,
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? CauceColors.peachPrimary : Colors.transparent;
    final fg = selected
        ? Colors.white
        : CauceColors.peachOnSurfaceVariant.withValues(alpha: 0.8);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: CauceColors.peachPrimary.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
