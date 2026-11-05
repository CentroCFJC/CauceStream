/// Controlador del inventario de dispositivos: unica fuente de verdad
/// compartida por Inicio y la pestana Dispositivos.
///
/// Mantiene la ultima lista conocida mientras refresca, para que la UI
/// no parpadee en cada actualizacion. Los conteos por estado alimentan
/// las metricas de la pantalla de Inicio.
///
/// El estado mostrado viene SIEMPRE del servidor: mientras el shell
/// principal esta visible, un sondeo REST periodico (polling) mantiene
/// el inventario al dia sin depender de gestos del usuario.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/network/api_exception.dart';
import '../models/assignment.dart';
import '../models/device.dart';
import '../services/assignment_service.dart';
import '../services/device_service.dart';

enum DevicesLoadStatus { idle, loading, ready, error }

class DevicesController extends ChangeNotifier with WidgetsBindingObserver {
  DevicesController({
    required DeviceService service,
    AssignmentService? assignmentService,
    DateTime Function()? now,
  }) : _service = service,
       _assignmentService = assignmentService,
       _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
  }

  final DeviceService _service;

  /// Reloj inyectable: en pruebas permite envejecer el sondeo de
  /// forma determinista sin esperar el tiempo real.
  final DateTime Function() _now;

  /// Servicio de dispositivos compartido (registro, autoconfig...).
  DeviceService get service => _service;

  /// Servicio de asignaciones compartido (detalle de dispositivo y
  /// detalle de medio). Opcional: sin el, el sondeo solo trae el
  /// inventario.
  final AssignmentService? _assignmentService;
  AssignmentService? get assignmentService => _assignmentService;

  static const Duration staleAfter = Duration(seconds: 15);

  /// Umbral de frescura para la UI: si el ultimo sondeo EXITOSO es mas
  /// viejo que esto, los estados mostrados son una foto antigua que no
  /// puede confirmarse como actual. Ortogonal a [Device.isOnline] y
  /// [Device.wsConnected]: no cambia el estado de ningun dispositivo,
  /// solo declara la edad de nuestro conocimiento.
  static const Duration staleDataAfter = Duration(seconds: 30);

  /// Momento del ultimo sondeo exitoso; null si nunca ha habido datos.
  DateTime? get fetchedAt => _fetchedAt;

  /// true cuando el snapshot mostrado esta caducado (sondeo fallido
  /// durante un rato). La UI lo usa para atenuar y anotar, nunca para
  /// marcar dispositivos como desconectados.
  bool get isStale {
    final fetched = _fetchedAt;
    if (fetched == null) return false;
    return _now().difference(fetched) > staleDataAfter;
  }

  /// Intervalo del sondeo periodico. El cliente late cada 10 s y el
  /// backend marca offline tras 30 s sin heartbeats: sondear cada 10 s
  /// mantiene el chip de estado al dia sin castigar la API.
  static const Duration pollInterval = Duration(seconds: 10);

  List<Device> _devices = const [];
  List<Device> get devices => _devices;

  /// Asignaciones vigentes (una por dispositivo), refrescadas en el
  /// mismo ciclo de sondeo que el inventario.
  List<Assignment> _assignments = const [];
  List<Assignment> get assignments => _assignments;

  DevicesLoadStatus _status = DevicesLoadStatus.idle;
  DevicesLoadStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// true mientras hay un sondeo en vuelo. La UI lo usa para el boton
  /// de refresh manual: un refresh con datos previos nunca bloquea la
  /// pantalla, solo este indicador.
  bool get isRefreshing => _fetching;

  DateTime? _fetchedAt;

  bool _fetching = false;

  Timer? _pollTimer;
  bool _pollingWanted = false;

  /// Activa el sondeo periodico del inventario. Idempotente; lo llama el
  /// shell principal mientras esta montado, asi Inicio y Dispositivos
  /// comparten un unico ciclo (sin timers por pantalla).
  void startPolling() {
    _pollingWanted = true;
    _startPollTimer();
  }

  /// Detiene el sondeo (al desmontar el shell o al ocultar la app).
  void stopPolling() {
    _pollingWanted = false;
    _stopPollTimer();
  }

  void _startPollTimer() {
    _pollTimer ??= Timer.periodic(pollInterval, (_) => refresh());
  }

  void _stopPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sondear solo con la app visible: en segundo plano no hay UI que
    // actualizar y el ahorro de bateria importa en los moviles de la
    // sala.
    if (state == AppLifecycleState.resumed) {
      if (_pollingWanted) _startPollTimer();
    } else {
      _stopPollTimer();
    }
  }

  @override
  void dispose() {
    stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Carga el inventario si aun no existe o si los datos conocidos ya
  /// caducaron. Las pantallas lo llaman al construirse.
  Future<void> ensureLoaded() async {
    final fetched = _fetchedAt;
    final fresh = fetched != null && _now().difference(fetched) < staleAfter;
    if (_fetching || (_devices.isNotEmpty && fresh)) return;
    await refresh();
  }

  /// Refresca el inventario contra la API. Nunca lanza: los fallos se
  /// exponen en [errorMessage] conservando la lista anterior. El sondeo
  /// periodico la reutiliza para reintentar silenciosamente cuando el
  /// servidor vuelve a responder.
  Future<void> refresh() async {
    if (_fetching) return;
    _fetching = true;
    // Solo la carga inicial pone `loading`: con un sondeo previo
    // exitoso (aunque la lista este vacia) el refresh es en segundo
    // plano y la pantalla conserva el ultimo inventario mostrado.
    if (_fetchedAt == null) {
      _status = DevicesLoadStatus.loading;
      notifyListeners();
    }
    try {
      _devices = await _service.listDevices();
      _fetchedAt = _now();
      _errorMessage = null;
      _status = DevicesLoadStatus.ready;
      await _refreshAssignments();
    } on ApiException catch (e) {
      _errorMessage = e.message;
      // Sin sondeo previo el fallo es pantalla de error; con datos
      // previos se conserva el ultimo estado (la caducidad se declara
      // via [isStale], nunca vaciando la lista).
      _status = _fetchedAt == null
          ? DevicesLoadStatus.error
          : DevicesLoadStatus.ready;
    } finally {
      _fetching = false;
      notifyListeners();
    }
  }

  /// Trae las asignaciones vigentes. Complementarias al inventario:
  /// un fallo puntual no marca error global ni ensucia el estado de
  /// los dispositivos; el siguiente ciclo del sondeo reintenta.
  Future<void> _refreshAssignments() async {
    final service = _assignmentService;
    if (service == null) return;
    try {
      _assignments = await service.getAssignments();
    } on ApiException {
      // Intencionalmente silencioso: ver arriba.
    }
  }

  /// Asignacion vigente de un dispositivo; null si no tiene.
  Assignment? assignmentOf(String deviceUid) {
    for (final a in _assignments) {
      if (a.deviceUid == deviceUid) return a;
    }
    return null;
  }

  int get onlineCount => _devices.where((d) => d.isOnline).length;
  int get offlineCount => _devices.where((d) => !d.isOnline).length;

  /// Activos: en linea y no en espera (device_state activo o nulo con
  /// heartbeat confirmado). En espera: en linea con device_state idle.
  /// Desconectados: sin heartbeat reciente. Las tres categorias suman
  /// el total del inventario.
  int get activeCount => _devices.where((d) => d.isActive).length;
  int get standbyCount => _devices.where((d) => d.isStandby).length;

  /// Primer dispositivo desconectado, para la alerta de la pantalla de
  /// Inicio.
  Device? get firstOffline {
    for (final d in _devices) {
      if (!d.isOnline) return d;
    }
    return null;
  }
}
