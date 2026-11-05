/// Resultado de un comando de energia (POST /api/devices/{uid}/power).
library;

/// El servidor ejecuta el comando con el controlador del `type` del
/// dispositivo (p. ej. ADB desde el servidor para google_tv/android_tv)
/// o, en su defecto, por el canal WebSocket del dispositivo.
///
/// `method`/`executed`/`success`/`detail` describen el intento (p. ej.
/// method 'adb', success false, detail 'sin IP reportada'). `command_id`
/// y `delivered` solo aplican al fallback WebSocket. El efecto real
/// (`device_state`) llega despues por heartbeat y se refleja con el
/// polling del inventario; no se persiste nada de esto en `Device`.
class PowerCommandResult {
  const PowerCommandResult({
    required this.deviceUid,
    required this.action,
    required this.method,
    required this.executed,
    required this.success,
    this.detail = '',
    this.commandId,
    this.delivered = false,
  });

  final String deviceUid;

  /// 'on' = encender (salir de espera).
  /// 'off' = entrar en espera (apagar pantalla; el equipo sigue vivo).
  final String action;

  /// Controlador que ejecutó el comando: 'adb', 'wol+adb', 'websocket'...
  final String method;

  /// false cuando el dispositivo ya estaba en el estado pedido.
  final bool executed;
  final bool success;
  final String detail;

  /// Solo para method 'websocket'.
  final int? commandId;
  final bool delivered;

  factory PowerCommandResult.fromJson(Map<String, dynamic> json) =>
      PowerCommandResult(
        deviceUid: json['device_uid'] as String,
        action: json['action'] as String,
        method: json['method'] as String? ?? 'websocket',
        executed: json['executed'] as bool? ?? false,
        success: json['success'] as bool? ?? (json['delivered'] as bool? ?? false),
        detail: json['detail'] as String? ?? '',
        commandId: json['command_id'] as int?,
        delivered: json['delivered'] as bool? ?? false,
      );
}
