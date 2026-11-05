/// Servicio del endpoint TEMPORAL de encendido/apagado maestro de la
/// sala. VER backend/docs/room_power_temporal.md: este contrato sera
/// reemplazado por el control maestro individualizado por dispositivo,
/// por eso vive aislado de [DeviceService].
///
/// Contrato real (permiso `devices.control` en ambos):
/// - POST /api/room/power   body {"action": "on"|"off"}
///   -> 202 {"action", "task_name"}: la tarea programada de Windows
///   (Cauce_ON / Cauce_OFF) fue DISPARADA, no completada. El
///   encendido/apagado real es asincronico.
/// - GET /api/room/power
///   -> 200 {"on": {...}, "off": {...}}: ultima ejecucion de cada
///   tarea segun el Programador de Tareas del servidor (fuente de
///   verdad; nada se persiste en la BD).
///
/// Errores:
/// - 502 {code: host_command_failed}: el servidor no pudo lanzar la
///   tarea de Windows (PowerShell/tarea programada caida).
/// - 403: sin `devices.control`. 401: sesion invalida.
library;

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../models/room_power.dart';

class RoomService {
  RoomService({required ApiClient client}) : _client = client;

  final ApiClient _client;

  /// Dispara la tarea maestra de encendido o apagado de la sala.
  ///
  /// Devuelve la confirmacion del disparo (202): NO garantiza que la
  /// sala este encendida/apagada; el resultado se verifica con
  /// [getStatus]. Lanza `ApiException` 502 (host_command_failed) si
  /// el servidor no pudo lanzar la tarea y 403 sin `devices.control`.
  Future<RoomPowerAccepted> setPower(RoomPowerAction action) async {
    final data = await _client.post(
      '${ApiConfig.roomPowerPath}/power',
      body: {'action': action.wireName},
    );
    return RoomPowerAccepted.fromJson(data as Map<String, dynamic>);
  }

  /// Estado de las tareas Cauce_ON y Cauce_OFF (ultima ejecucion,
  /// resultado y si alguna esta corriendo). Fuente de verdad del
  /// resultado tras un [setPower].
  Future<RoomPowerStatus> getStatus() async {
    final data = await _client.get('${ApiConfig.roomPowerPath}/power');
    return RoomPowerStatus.fromJson(data as Map<String, dynamic>);
  }
}
