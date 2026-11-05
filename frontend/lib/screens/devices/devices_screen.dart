/// Pestana Dispositivos: inventario registrado en el backend.
///
/// La lista y el estado de cada dispositivo (conectividad + estado
/// operativo) provienen de GET /api/devices a traves de
/// [DevicesController]. La busqueda filtra el inventario en memoria;
/// los filtros rapidos y las acciones por tarjeta todavia no estan
/// conectados a la API. El Control Maestro si usa el endpoint
/// TEMPORAL POST/GET /api/room/power (ver
/// backend/docs/room_power_temporal.md).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../controllers/devices_controller.dart';
import '../../controllers/media_library_controller.dart';
import '../../controllers/room_controller.dart';
import '../../core/capabilities.dart';
import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../models/device.dart';
import '../../models/media.dart';
import '../../models/room_power.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/identity_widgets.dart';
import '../../widgets/organic_background.dart';
import '../../widgets/stale_data_notice.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _searchController = TextEditingController();

  /// El Control Maestro nace cerrado: las acciones de sala solo se
  /// despliegan al expandir la tarjeta.
  bool _masterExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DevicesController>().ensureLoaded();
      // La biblioteca resuelve el nombre del medio en reproduccion
      // (el heartbeat reporta el id) en las tarjetas del inventario.
      context.read<MediaLibraryController>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _notAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Las operaciones sobre dispositivos llegan en una fase posterior.',
        ),
      ),
    );
  }

  /// Confirmacion antes de disparar la tarea maestra: afecta a toda
  /// la sala, no a un dispositivo. Solo con `confirmed == true` se
  /// envia el POST.
  Future<void> _confirmRoomPower(RoomPowerAction action) async {
    final isOn = action == RoomPowerAction.on;
    // Se capturan ANTES del await: nada de context tras la pausa.
    final room = context.read<RoomController>();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: CauceColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: CauceColors.peachSurfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOn ? Icons.power_settings_new : Icons.power_off,
                size: 28,
                color: isOn ? CauceColors.success : CauceColors.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isOn ? 'ENCENDER SALA' : 'APAGAR SALA',
              style: const TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CauceColors.maroon,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isOn
                  ? 'Se disparara la tarea Cauce_ON en el servidor de la '
                        'sala. El encendido real de todos los equipos tarda '
                        'unos segundos; no es inmediato.'
                  : 'Se disparara la tarea Cauce_OFF en el servidor de la '
                        'sala. El apagado real de todos los equipos tarda '
                        'unos segundos; no es inmediato.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 13,
                height: 1.4,
                color: CauceColors.peachOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: isOn
                      ? CauceColors.success
                      : CauceColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(isOn ? 'Encender sala' : 'Apagar sala'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await room.setPower(action);
    if (!mounted) return;
    final message = room.message;
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<Device> _filtered(List<Device> devices) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return devices;
    return devices
        .where(
          (d) =>
              d.name.toLowerCase().contains(query) ||
              d.type.toLowerCase().contains(query) ||
              d.deviceUid.toLowerCase().contains(query) ||
              (d.ipAddress ?? '').contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(color: CauceColors.peachSurface),
        const OrganicBackground(
          topRight: true,
          bottomLeft: false,
          baseColor: CauceColors.peachSurface,
        ),
        Column(
          children: [
            TabHeader(
              title: 'Dispositivos',
              onAvatarTap: () =>
                  Navigator.of(context).pushNamed(Routes.profile),
            ),
            Expanded(
              child: Consumer<DevicesController>(
                builder: (context, controller, _) {
                  // Pantalla de carga solo en la carga inicial (sin
                  // ningun sondeo previo): los refreshes posteriores,
                  // incluso con inventario vacio, no reemplazan la UI.
                  if (controller.status == DevicesLoadStatus.loading &&
                      controller.fetchedAt == null) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: CauceColors.peachPrimary,
                      ),
                    );
                  }
                  return Stack(
                    children: [
                      RefreshIndicator(
                        color: CauceColors.peachPrimary,
                        onRefresh: () => controller.refresh(),
                        child: Consumer<MediaLibraryController>(
                          builder: (context, library, _) =>
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  16,
                                  24,
                                  140,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (controller.isStale &&
                                        controller.devices.isNotEmpty) ...[
                                      StaleDataNotice(
                                        fetchedAt: controller.fetchedAt,
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    if (canControlDevices(context)) ...[
                                      Consumer<RoomController>(
                                        builder: (context, room, _) =>
                                            _MasterControlCard(
                                              deviceCount:
                                                  controller.devices.length,
                                              expanded: _masterExpanded,
                                              onToggle: () {
                                                setState(
                                                  () => _masterExpanded =
                                                      !_masterExpanded,
                                                );
                                                // Al desplegar se trae el
                                                // estado de las tareas (GET).
                                                if (_masterExpanded) {
                                                  room.refreshStatus();
                                                }
                                              },
                                              onPower: _confirmRoomPower,
                                              sending: room.isSending,
                                              status: room.status,
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    _SearchBar(
                                      controller: _searchController,
                                      onChanged: (_) => setState(() {}),
                                      onRefresh: () => context
                                          .read<DevicesController>()
                                          .refresh(),
                                      refreshing: controller.isRefreshing,
                                    ),
                                    const SizedBox(height: 12),
                                    const _FilterChips(),
                                    const SizedBox(height: 16),
                                    ..._buildBody(context, controller, library),
                                  ],
                                ),
                              ),
                        ),
                      ),
                      // Mismo comportamiento que "Nuevo Medio" en la
                      // biblioteca: accion flotante, no boton estatico.
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton.extended(
                          onPressed: () => Navigator.of(
                            context,
                          ).pushNamed(Routes.deviceRegister),
                          backgroundColor: CauceColors.peachPrimaryContainer,
                          foregroundColor: Colors.white,
                          icon: const Icon(Icons.add_circle, size: 22),
                          label: const Text(
                            'Nuevo Dispositivo',
                            style: TextStyle(
                              fontFamily: CauceTheme.bodyFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    DevicesController controller,
    MediaLibraryController library,
  ) {
    if (controller.status == DevicesLoadStatus.error &&
        controller.devices.isEmpty) {
      return [
        _NoticeCard(
          icon: Icons.wifi_off,
          message:
              controller.errorMessage ??
              'No fue posible consultar el inventario.',
          actionLabel: 'Reintentar',
          onAction: () => controller.refresh(),
        ),
      ];
    }
    final devices = _filtered(controller.devices);
    if (controller.devices.isNotEmpty && devices.isEmpty) {
      return [
        const _NoticeCard(
          icon: Icons.search_off,
          message: 'Ningun dispositivo coincide con la busqueda.',
        ),
      ];
    }
    if (devices.isEmpty) {
      return [
        const _NoticeCard(
          icon: Icons.devices_other,
          message:
              'Todavia no hay dispositivos registrados. Vincula el primero '
              'para verlo aqui con su estado.',
        ),
      ];
    }
    return [
      for (final device in devices) ...[
        _DeviceCard(
          device: device,
          playing: playingMedia(device, library.media),
          onAction: () => _notAvailable(context),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: CauceColors.peachSecondary),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
              height: 1.4,
              color: CauceColors.peachOnSurfaceVariant,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: CauceColors.peachPrimaryContainer,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _MasterControlCard extends StatelessWidget {
  const _MasterControlCard({
    required this.deviceCount,
    required this.expanded,
    required this.onToggle,
    required this.onPower,
    required this.sending,
    required this.status,
  });

  final int deviceCount;

  /// Desplegable de sala: cerrado por defecto.
  final bool expanded;
  final VoidCallback onToggle;

  /// Dispara la confirmacion de la accion maestra correspondiente.
  final ValueChanged<RoomPowerAction> onPower;

  /// true mientras viaja el POST /room/power: ambas acciones se
  /// bloquean y muestran progreso (nada de estado optimista).
  final bool sending;

  /// Ultimo estado conocido de las tareas Cauce_ON / Cauce_OFF.
  final RoomPowerStatus? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CauceColors.darkTeal,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: CauceColors.darkTeal.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.bolt, size: 22, color: CauceColors.yellow),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Control Maestro de Sala',
                            style: const TextStyle(
                              fontFamily: CauceTheme.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '$deviceCount dispositivos vinculados',
                            style: TextStyle(
                              fontFamily: CauceTheme.bodyFont,
                              fontSize: 11,
                              color: CauceColors.cream.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0 : 0.5,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_less,
                        size: 22,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOut,
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              child: Column(
                children: [
                  _MasterAction(
                    color: CauceColors.teal,
                    icon: Icons.power_settings_new,
                    title: 'Encender Sala',
                    subtitle:
                        status?.taskFor(RoomPowerAction.on).resultLabel ??
                        'Activar $deviceCount dispositivos',
                    busy: sending,
                    onTap: () => onPower(RoomPowerAction.on),
                  ),
                  const SizedBox(height: 12),
                  _MasterAction(
                    color: CauceColors.maroon,
                    icon: Icons.power_off,
                    title: 'Apagar Sala',
                    subtitle:
                        status?.taskFor(RoomPowerAction.off).resultLabel ??
                        'Suspender circuito',
                    busy: sending,
                    onTap: () => onPower(RoomPowerAction.off),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _MasterAction extends StatelessWidget {
  const _MasterAction({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;

  /// true mientras viaja el POST /room/power: la accion no responde
  /// y el icono se reemplaza por un indicador de progreso.
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: busy ? color.withValues(alpha: 0.6) : color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pin, size: 13, color: CauceColors.yellow),
                    const SizedBox(width: 4),
                    Text(
                      'PIN',
                      style: TextStyle(
                        fontFamily: CauceTheme.displayFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: CauceColors.yellow,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: CauceTheme.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 12,
                        color: CauceColors.cream.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Icon(icon, size: 26, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    this.onChanged,
    this.onRefresh,
    this.refreshing = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  /// Refresh manual del inventario (GET /api/devices). Con null no se
  /// muestra el boton.
  final VoidCallback? onRefresh;

  /// true mientras corre ese refresh: el boton muestra progreso en
  /// lugar del icono, sin tapar la lista.
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    // Variable local para que Dart promueva el nullable dentro del
    // spread: los campos publicos no se promueven.
    final refresh = onRefresh;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 20,
                  color: CauceColors.peachOnSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: true,
                    onChanged: onChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, sala o IP...',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontFamily: CauceTheme.bodyFont,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (refresh != null) ...[
          const SizedBox(width: 8),
          _RefreshButton(onTap: refresh, refreshing: refreshing),
        ],
        const SizedBox(width: 8),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: CauceColors.peachSurfaceContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.tune,
            size: 18,
            color: CauceColors.peachOnSurface,
          ),
        ),
      ],
    );
  }
}

/// Boton circular de refresh manual del inventario. Mientras la
/// peticion esta en vuelo muestra un indicador de progreso chico y no
/// responde a toques (el [DevicesController.refresh] es idempotente).
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onTap, required this.refreshing});

  final VoidCallback onTap;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: CauceColors.peachSurfaceContainer,
        shape: BoxShape.circle,
      ),
      child: refreshing
          ? const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CauceColors.peachOnSurface,
              ),
            )
          : InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const Icon(
                Icons.refresh,
                size: 18,
                color: CauceColors.peachOnSurface,
              ),
            ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips();

  static const _filters = [
    ('Todas', true),
    ('VR', false),
    ('AR', false),
    ('Tactiles', false),
    ('Totems', false),
    ('Televisores', false),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, selected) = _filters[index];
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 20 : 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: selected ? CauceColors.peachPrimary : Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : CauceColors.peachOnSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.playing,
    required this.onAction,
  });

  final Device device;

  /// Medio en reproduccion resuelto contra la biblioteca; null si
  /// no reporta o la biblioteca no lo tiene.
  final Media? playing;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final offline = !device.isOnline;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).pushNamed(Routes.deviceDetail, arguments: device),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: offline
                          ? CauceColors.peachErrorContainer
                          : CauceColors.peachSurfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: offline
                        ? const Icon(
                            Icons.tv_off,
                            size: 26,
                            color: CauceColors.maroon,
                          )
                        : Icon(
                            device.typeIcon,
                            size: 26,
                            color: CauceColors.peachSecondary,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: CauceTheme.displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: CauceColors.peachOnSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _subtitle(offline),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    status: device.cauceStatus,
                    label: device.statusLabel,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: offline
                      ? CauceColors.peachErrorContainer.withValues(alpha: 0.4)
                      : CauceColors.peachSurfaceContainerLow.withValues(
                          alpha: 0.7,
                        ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      offline ? Icons.schedule : Icons.lan,
                      size: 16,
                      color: offline
                          ? CauceColors.maroon
                          : CauceColors.peachOnSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        offline
                            ? (device.relativeLastSeen == null
                                  ? 'Nunca se ha comunicado'
                                  : 'Ultimo latido ${device.relativeLastSeen}')
                            : (device.ipAddress ?? 'IP no reportada'),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: CauceTheme.displayFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: CauceColors.peachOnSurfaceVariant,
                        ),
                      ),
                    ),
                    if (!offline) ...[
                      Text(
                        device.relativeLastSeen ?? '',
                        style: const TextStyle(
                          fontFamily: CauceTheme.displayFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CauceColors.peachOnSurfaceVariant,
                        ),
                      ),
                    ] else ...[
                      InkWell(
                        onTap: onAction,
                        child: const _RoundIcon(icon: Icons.replay),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onAction,
                        child: const _RoundIcon(icon: Icons.tune),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Linea secundaria de la tarjeta: icono del tipo de medio + nombre
  /// cuando hay reproduccion (triangulo de play rojo para video,
  /// icono de imagen/enlace para el resto); si no reporta, el tipo
  /// del inventario.
  Widget _subtitle(bool offline) {
    final color = offline
        ? CauceColors.maroon
        : CauceColors.peachOnSurfaceVariant;
    final style = TextStyle(
      fontFamily: CauceTheme.bodyFont,
      fontSize: 12,
      color: color,
      fontWeight: offline ? FontWeight.w600 : FontWeight.w400,
    );
    final media = playing;
    if (media == null) {
      return Text(
        device.subtitle,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Row(
      children: [
        Icon(
          media.playingIcon,
          size: 15,
          color: media.isVideo ? CauceColors.error : color,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            media.name,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4),
        ],
      ),
      child: Icon(icon, size: 16, color: CauceColors.peachSecondary),
    );
  }
}
