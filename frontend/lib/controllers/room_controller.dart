/// Controlador del encendido/apagado maestro de la sala (endpoint
/// TEMPORAL, ver backend/docs/room_power_temporal.md).
///
/// Estado: idle (nunca/ultima accion terminada) -> enviando (POST en
/// curso) -> aceptado (202: la tarea fue disparada, NO completada) o
/// error (fallo clasificado). Nada de estado optimista: la fuente de
/// verdad del resultado es el GET, expuesto en [status].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../models/room_power.dart';
import '../services/room_service.dart';

enum RoomPowerPhase { idle, sending, accepted, error }

class RoomController extends ChangeNotifier {
  RoomController({required RoomService service}) : _service = service;

  final RoomService _service;

  RoomPowerPhase _phase = RoomPowerPhase.idle;
  RoomPowerPhase get phase => _phase;

  /// Ultima accion confirmada por el servidor (202) o fallida.
  RoomPowerAction? _lastAction;
  RoomPowerAction? get lastAction => _lastAction;

  /// Mensaje de la ultima transicion (aceptacion o error) para la UI.
  String? _message;
  String? get message => _message;

  /// Ultimo estado conocido de las tareas Cauce_ON / Cauce_OFF.
  /// Se conserva el anterior si un refresco falla.
  RoomPowerStatus? _status;
  RoomPowerStatus? get status => _status;

  /// Mientras alguna tarea este corriendo se sondea el GET para que
  /// la etiqueta "Ejecutandose ahora" desaparezca sola al terminar.
  static const _pollInterval = Duration(seconds: 5);
  static const _maxPolls = 60; // Techo: 5 minutos de sondeo.
  Timer? _pollTimer;
  int _polls = 0;

  bool get isSending => _phase == RoomPowerPhase.sending;

  /// Dispara la tarea maestra de encendido/apagado. Nunca lanza: los
  /// fallos se clasifican en [message] y [phase] (error).
  ///
  /// Con 202 pasa a `accepted` con un mensaje de "orden enviada"
  /// (nunca "sala encendida": el disparo no garantiza nada todavia) y
  /// refresca [status] contra el GET para que la UI muestre la ultima
  /// ejecucion de la tarea correspondiente.
  Future<void> setPower(RoomPowerAction action) async {
    if (isSending) return;
    _phase = RoomPowerPhase.sending;
    _message = null;
    notifyListeners();
    try {
      final accepted = await _service.setPower(action);
      _lastAction = action;
      _phase = RoomPowerPhase.accepted;
      _message =
          'Orden enviada: tarea ${accepted.taskName} disparada. El '
          '${action == RoomPowerAction.on ? 'encendido' : 'apagado'} real '
          'de la sala tarda unos segundos.';
      notifyListeners();
      await refreshStatus();
    } on ApiException catch (e) {
      _lastAction = action;
      _phase = RoomPowerPhase.error;
      _message = _messageFor(e);
      notifyListeners();
    }
  }

  /// Refresca el estado de las tareas. Nunca lanza; conserva el
  /// ultimo estado conocido en fallo.
  Future<void> refreshStatus() async {
    try {
      _status = await _service.getStatus();
    } on ApiException {
      // Intencionalmente silencioso: la UI sigue mostrando el ultimo
      // estado conocido; el proximo refresco reintenta.
    }
    _syncPolling();
    notifyListeners();
  }

  /// Arranca o detiene el sondeo segun el ultimo estado conocido: si
  /// alguna tarea corre, se consulta cada [_pollInterval] hasta que
  /// termine (o hasta [_maxPolls] consultas, para no sondear para
  /// siempre si el host queda inconsistente).
  void _syncPolling() {
    final anyRunning =
        _status != null && (_status!.on.running || _status!.off.running);
    if (anyRunning && _pollTimer == null) {
      _polls = 0;
      _pollTimer = Timer.periodic(_pollInterval, (_) async {
        _polls++;
        if (_polls >= _maxPolls) {
          _stopPolling();
          return;
        }
        await refreshStatus();
      });
    } else if (!anyRunning) {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  String _messageFor(ApiException e) {
    if (e.statusCode == 502 && e.code == 'host_command_failed') {
      return 'El servidor no pudo lanzar la tarea de Windows '
          '(PowerShell o tarea programada caida). Verifica el servidor '
          'de la sala y reintenta manualmente.';
    }
    if (e.isAuthError) {
      return 'No tienes permiso para controlar la sala.';
    }
    return e.message;
  }
}
