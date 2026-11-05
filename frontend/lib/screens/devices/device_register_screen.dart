/// Registro de dispositivo con autodescubrimiento.
///
/// Flujo: al abrir se activa `POST /api/devices/autoconfig` y se
/// sondea `GET /api/devices/autoconfig/pending` cada 3 segundos
/// (sin peticiones simultaneas). Al seleccionar un equipo detectado
/// se conserva su `device_uid` y se rellena la IP (editable). El
/// registro reusa `POST /api/devices` sin puerto. Al salir de la
/// pantalla se desactiva el autodescubrimiento.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/devices_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../models/device.dart';
import '../../services/device_service.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/organic_background.dart';

/// Fase del autodescubrimiento dentro de la pantalla.
enum _DiscoveryPhase { activating, searching, error }

class DeviceRegisterScreen extends StatefulWidget {
  const DeviceRegisterScreen({super.key});

  /// Opciones de tipo de dispositivo: (icono, etiqueta visible, type
  /// canonico del backend). El type dirige el controlador de energia del
  /// servidor (app/power del backend): google_tv/android_tv se controlan
  /// por ADB desde el servidor.
  static const stationOptions = <(IconData, String, String)>[
    (Icons.tv, 'Google TV / Android TV', 'google_tv'),
    (Icons.tv, 'TV Samsung (MDC)', 'samsung_tv'),
    (Icons.view_in_ar, 'Visor VR', 'visor_vr'),
    (Icons.tablet, 'Tablet', 'tablet'),
    (Icons.memory, 'Raspberry Pi', 'raspberry_pi'),
    (Icons.computer, 'PC Windows', 'windows_pc'),
    (Icons.category, 'Otro', 'otro'),
  ];

  @override
  State<DeviceRegisterScreen> createState() => _DeviceRegisterScreenState();
}

class _DeviceRegisterScreenState extends State<DeviceRegisterScreen> {
  static const _stations = DeviceRegisterScreen.stationOptions;

  static const _pollInterval = Duration(seconds: 3);

  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _macController = TextEditingController();

  int _mode = 0; // 0 = Autoconfiguracion (LAN), 1 = Manual
  int _station = 6; // Otro (por defecto)

  _DiscoveryPhase _phase = _DiscoveryPhase.activating;
  String? _phaseError;

  List<PendingDevice> _pending = const [];
  String? _pollError; // fallo del ultimo sondeo (no borra la lista)

  String? _selectedUid;
  bool _selectionStale = false;

  bool _saving = false;
  String? _saveError;

  Timer? _pollTimer;
  bool _polling = false;
  bool _autoconfigActive = false;

  // Capturado en initState: los callbacks del temporizador y el
  // dispose usan el servicio despues de perder el contexto.
  late final DeviceService _deviceService;

  @override
  void initState() {
    super.initState();
    _deviceService = context.read<DevicesController>().service;
    _enableAutoconfig();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nameController.dispose();
    _ipController.dispose();
    _macController.dispose();
    // La desactivacion es un efecto lateral pendiente: no se espera.
    if (_autoconfigActive) {
      unawaited(_disableAutoconfig());
    }
    super.dispose();
  }

  DeviceService get _service => _deviceService;

  Future<void> _enableAutoconfig() async {
    setState(() => _phase = _DiscoveryPhase.activating);
    try {
      await _service.setAutoconfigEnabled(true);
      if (!mounted) return;
      _autoconfigActive = true;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) => _pollPending());
      unawaited(_pollPending());
      setState(() => _phase = _DiscoveryPhase.searching);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _DiscoveryPhase.error;
        _phaseError = e.message;
      });
    }
  }

  Future<void> _disableAutoconfig() async {
    try {
      await _service.setAutoconfigEnabled(false);
    } on ApiException {
      // La desactivacion es best-effort: no interrumpe el cierre.
    }
  }

  /// Consulta los dispositivos pendientes. El guard evita peticiones
  /// simultaneas; un fallo temporal no borra la lista ni la seleccion.
  Future<void> _pollPending() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final pending = await _service.getPendingDevices();
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _pollError = null;
        _selectionStale =
            _selectedUid != null &&
            !pending.any((d) => d.deviceUid == _selectedUid);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _pollError = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pollError = 'Respuesta inesperada del servidor.');
    } finally {
      _polling = false;
    }
  }

  void _selectDevice(PendingDevice device) {
    setState(() {
      _selectedUid = device.deviceUid;
      _selectionStale = false;
      _ipController.text = device.ipAddress ?? _ipController.text;
      // Nombre sugerido: el identificador que el equipo reporta.
      if (_nameController.text.isEmpty) {
        _nameController.text = device.deviceUid;
      }
      _saveError = null;
    });
  }

  void _onModeChanged(int mode) {
    setState(() {
      _mode = mode;
      _selectedUid = null;
      _selectionStale = false;
      _saveError = null;
    });
  }

  Future<void> _onSave() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _saveError = 'Escribe un nombre para el dispositivo.');
      return;
    }
    if (_mode == 0) {
      if (_selectedUid == null) {
        setState(
          () => _saveError =
              'Selecciona un dispositivo detectado o usa la configuracion manual.',
        );
        return;
      }
      if (_selectionStale) {
        setState(
          () => _saveError =
              'El dispositivo ya no aparece en la red. Vuelve a buscarlo y selecciona otro.',
        );
        return;
      }
    }

    // En manual, el identificador del nodo es el nombre ingresado.
    final deviceUid = _mode == 0 ? _selectedUid! : name;
    final ip = _ipController.text.trim();
    final mac = _macController.text.trim();

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _service.registerDevice(
        deviceUid: deviceUid,
        name: name,
        type: _stations[_station].$3,
        ipAddress: ip.isEmpty ? null : ip,
        macAddress: mac.isEmpty ? null : mac,
      );
      if (!mounted) return;
      // Actualiza el inventario compartido antes de salir.
      unawaited(context.read<DevicesController>().refresh());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dispositivo "$name" registrado.'),
          backgroundColor: CauceColors.teal,
        ),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CauceColors.creamSurface,
      body: Stack(
        children: [
          const OrganicBackground(baseColor: CauceColors.creamSurface),
          Column(
            children: [
              const StackHeader(
                title: 'Nuevo\nDispositivo',
                closeInsteadOfBack: true,
                showLogo: false,
                titleFontSize: 16,
                backgroundColor: CauceColors.creamSurface,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    32 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ModeSelector(mode: _mode, onChanged: _onModeChanged),
                      if (_mode == 0) ...[
                        const SizedBox(height: 20),
                        _DiscoveryPanel(
                          phase: _phase,
                          phaseError: _phaseError,
                          pollError: _pollError,
                          pending: _pending,
                          selectedUid: _selectedUid,
                          stale: _selectionStale,
                          onSelect: _selectDevice,
                          onRetry: _enableAutoconfig,
                        ),
                      ],
                      const SizedBox(height: 20),
                      _NodeForm(
                        nameController: _nameController,
                        ipController: _ipController,
                        macController: _macController,
                        station: _station,
                        manual: _mode == 1,
                        stale: _selectionStale,
                        onStationSelected: (i) => setState(() => _station = i),
                      ),
                      const SizedBox(height: 24),
                      _SaveButton(
                        saving: _saving,
                        error: _saveError,
                        onPressed: _onSave,
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final int mode;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              icon: Icons.sensors,
              label: 'Autoconfiguracion',
              selected: mode == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _ModeButton(
              icon: Icons.edit_note,
              label: 'Manual',
              selected: mode == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
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
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? CauceColors.creamPrimary
                    : CauceColors.creamOnSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? CauceColors.creamOnSurface
                        : CauceColors.creamOnSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel de autodescubrimiento: estados de activacion, busqueda,
/// equipos detectados y errores de consulta.
class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({
    required this.phase,
    required this.phaseError,
    required this.pollError,
    required this.pending,
    required this.selectedUid,
    required this.stale,
    required this.onSelect,
    required this.onRetry,
  });

  final _DiscoveryPhase phase;
  final String? phaseError;
  final String? pollError;
  final List<PendingDevice> pending;
  final String? selectedUid;
  final bool stale;
  final ValueChanged<PendingDevice> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, size: 18, color: CauceColors.teal),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Terminales detectadas en la red local',
                  style: TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: CauceColors.creamOnSurface,
                  ),
                ),
              ),
              Text(
                '${pending.length} nodos',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CauceColors.creamSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (phase) {
      case _DiscoveryPhase.activating:
        return const _DiscoveryHint(
          icon: Icons.sensors,
          child: Text('Activando autodescubrimiento...'),
        );
      case _DiscoveryPhase.error:
        return _DiscoveryHint(
          icon: Icons.wifi_off,
          child: Column(
            children: [
              Text(
                phaseError ?? 'No fue posible activar el autodescubrimiento.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ),
        );
      case _DiscoveryPhase.searching:
        if (pending.isEmpty) {
          return Column(
            children: [
              const _DiscoveryHint(
                icon: Icons.search,
                child: Text('Buscando dispositivos...'),
              ),
              if (stale) ...[
                const SizedBox(height: 8),
                const _InlineNotice(
                  icon: Icons.warning_amber,
                  text:
                      'El dispositivo seleccionado ya no aparece en la red. Vuelve a buscarlo.',
                ),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < pending.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _DiscoveredCard(
                device: pending[i],
                selected: pending[i].deviceUid == selectedUid,
                onTap: () => onSelect(pending[i]),
              ),
            ],
            if (stale) ...[
              const SizedBox(height: 8),
              _InlineNotice(
                icon: Icons.warning_amber,
                text:
                    'El dispositivo seleccionado ya no aparece en la red. Vuelve a buscarlo.',
              ),
            ],
            if (pollError != null) ...[
              const SizedBox(height: 8),
              _InlineNotice(
                icon: Icons.wifi_off,
                text: 'Ultimo sondeo con errores: $pollError',
              ),
            ],
          ],
        );
    }
  }
}

class _DiscoveryHint extends StatelessWidget {
  const _DiscoveryHint({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: CauceColors.creamSecondary),
          const SizedBox(height: 8),
          DefaultTextStyle(
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
              height: 1.4,
              color: CauceColors.creamOnSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: CauceColors.creamSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 11,
                height: 1.3,
                color: CauceColors.creamOnSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveredCard extends StatelessWidget {
  const _DiscoveredCard({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final PendingDevice device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stateLabel = device.stateLabel;
    return Material(
      color: selected ? Colors.white : CauceColors.creamSurfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CauceColors.creamPrimary, width: 2),
                )
              : null,
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected
                      ? CauceColors.creamPrimary
                      : CauceColors.creamSurfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceUid,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CauceColors.creamOnSurface,
                      ),
                    ),
                    Text(
                      'IP: ${device.ipAddress ?? 'no reportada'}',
                      style: TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 12,
                        color: CauceColors.creamOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (stateLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: CauceColors.creamSecondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    stateLabel,
                    style: TextStyle(
                      fontFamily: CauceTheme.bodyFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: CauceColors.creamSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeForm extends StatelessWidget {
  const _NodeForm({
    required this.nameController,
    required this.ipController,
    required this.macController,
    required this.station,
    required this.manual,
    required this.stale,
    required this.onStationSelected,
  });

  final TextEditingController nameController;
  final TextEditingController ipController;
  final TextEditingController macController;
  final int station;
  final bool manual;
  final bool stale;
  final ValueChanged<int> onStationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Parametros del Nodo',
                  style: TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: CauceColors.creamOnSurface,
                  ),
                ),
              ),
              Text(
                'Editables',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: CauceColors.creamSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FieldLabel(label: 'Nombre del Dispositivo', required: true),
          const SizedBox(height: 6),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge, size: 20),
              hintText: 'Ej. Totem Sala 1',
            ),
          ),
          if (manual) ...[
            const SizedBox(height: 6),
            Text(
              'En modo manual el identificador del equipo (device_uid) se toma del nombre.',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 11,
                color: CauceColors.creamOnSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const _FieldLabel(label: 'Direccion IPv4'),
          const SizedBox(height: 6),
          TextField(
            controller: ipController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.dns, size: 18),
              hintText: '10.15.1.185',
            ),
          ),
          const SizedBox(height: 16),
          const _FieldLabel(
            label: 'MAC (Wake-on-LAN, opcional)',
          ),
          const SizedBox(height: 6),
          TextField(
            controller: macController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.wifi, size: 18),
              hintText: '7C:01:3E:7A:7D:52',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'La usa el servidor para encender el equipo apagado (Wake-on-LAN). Si el cliente la reporta por heartbeat no hace falta escribirla.',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 11,
              color: CauceColors.creamOnSurfaceVariant,
            ),
          ),
          if (stale) ...[
            const SizedBox(height: 6),
            Text(
              'El equipo detectado dejo de reportar: confirma que siga en la red antes de guardar.',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 11,
                color: CauceColors.creamSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const _FieldLabel(label: 'Tipo de Dispositivo'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              for (
                var i = 0;
                i < _DeviceRegisterScreenState._stations.length;
                i++
              )
                _StationChip(
                  icon: _DeviceRegisterScreenState._stations[i].$1,
                  label: _DeviceRegisterScreenState._stations[i].$2,
                  selected: i == station,
                  onTap: () => onStationSelected(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: CauceTheme.bodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: CauceColors.creamOnSurface,
        ),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: CauceColors.creamPrimary),
            ),
        ],
      ),
    );
  }
}

class _StationChip extends StatelessWidget {
  const _StationChip({
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
    return Material(
      color: selected
          ? CauceColors.creamSecondary
          : CauceColors.creamSurfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? Colors.white
                  : CauceColors.creamOnSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : CauceColors.creamOnSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.saving,
    required this.error,
    required this.onPressed,
  });

  final bool saving;
  final String? error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: saving ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: CauceColors.creamPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save, size: 20),
          label: Text(
            saving ? 'Registrando dispositivo...' : 'Guardar dispositivo',
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 16,
                color: CauceColors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  error!,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 12,
                    height: 1.3,
                    color: CauceColors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
