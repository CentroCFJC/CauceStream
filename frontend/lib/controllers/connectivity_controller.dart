/// Sondeo de conectividad con el servidor Cauce: alimenta el badge
/// LAN de los encabezados.
///
/// Mismo ciclo de vida que [DevicesController]: un unico timer
/// compartido mientras la app esta en primer plano, pausado al pasar
/// a segundo plano (ahorro de bateria) y con un check puntual al
/// volver. El estado solo notifica cuando cambia; las comprobaciones
/// nunca se solapan y la interfaz nunca se bloquea (todo es async).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/config/api_config.dart';
import '../services/connectivity_service.dart';

/// Estado del enlace con el servidor Cauce.
enum LanStatus {
  /// Comprobacion inicial en curso: neutro, sin afirmar conexion.
  checking,

  /// La API del servidor responde correctamente.
  active,

  /// No se consigue comunicacion valida con la API.
  inactive,
}

class ConnectivityController extends ChangeNotifier
    with WidgetsBindingObserver {
  ConnectivityController({ConnectivityService? service, Duration? interval})
    : _service = service ?? ConnectivityService(),
      interval = interval ?? ApiConfig.connectivityCheckInterval {
    WidgetsBinding.instance.addObserver(this);
    // La URL activa queda en el log: si el badge cae en "Inactivo",
    // aqui se ve a que servidor se le esta pidiendo /api/health.
    debugPrint(
      '[Cauce] sondeo LAN contra ${ApiConfig.activeServerUrl}'
      '/api${ApiConfig.healthPath} cada '
      '${(interval ?? ApiConfig.connectivityCheckInterval).inSeconds}s',
    );
    // Comprobacion inicial inmediata; luego el sondeo periodico.
    unawaited(_tick());
    _startTimer();
  }

  final ConnectivityService _service;

  /// Intervalo entre comprobaciones (configurable por entorno).
  final Duration interval;

  LanStatus _status = LanStatus.checking;
  LanStatus get status => _status;

  bool _checking = false;
  Timer? _timer;
  bool _pollingWanted = true;

  /// Comprobacion periodica; idempotente y sin solapamientos.
  void _startTimer() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Una sola comprobacion en vuelo: si el timer vence mientras una
  /// peticion sigue abierta, se ignora esa vuelta.
  Future<void> _tick() async {
    if (_checking) return;
    _checking = true;
    final reachable = await _service.check();
    _checking = false;
    _update(reachable ? LanStatus.active : LanStatus.inactive);
  }

  /// Solo notifica cuando el estado cambia: nada de reconstruir la
  /// interfaz en cada ciclo si nada se movio.
  void _update(LanStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sondear solo con la app visible, igual que el inventario. Al
    // volver a primer plano se comprueba de inmediato: la red pudo
    // cambiar mientras la app estuve en segundo plano.
    if (state == AppLifecycleState.resumed) {
      if (_pollingWanted) {
        _startTimer();
        unawaited(_tick());
      }
    } else {
      _stopTimer();
    }
  }

  @override
  void dispose() {
    _pollingWanted = false;
    _stopTimer();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
