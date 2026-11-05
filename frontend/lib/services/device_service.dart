/// Servicio de dispositivos contra el backend Cauce.
///
/// Contratos reales usados por el inventario y el registro:
/// - GET  /api/devices                  (permiso `devices.view`)
/// - GET  /api/devices/{uid}            (permiso `devices.view`)
/// - POST /api/devices                  (permiso `devices.manage`)
/// - POST /api/devices/autoconfig       (permiso `devices.manage`)
/// - GET  /api/devices/autoconfig/pending (permiso `devices.manage`)
/// - POST /api/devices/{uid}/power       (permiso `devices.control`)
library;

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../models/device.dart';
import '../models/power_command.dart';

class DeviceService {
  DeviceService({required ApiClient client}) : _client = client;

  final ApiClient _client;

  /// Lista el inventario completo con el estado que el servidor deriva
  /// de los heartbeats (conectividad y estado operativo).
  Future<List<Device>> listDevices() async {
    final data = await _client.get(ApiConfig.devicesPath);
    return (data as List<dynamic>)
        .map((item) => Device.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Obtiene un dispositivo por su identificador estable.
  ///
  /// El uid es el nombre que expone el SO y puede contener espacios u
  /// otros caracteres: viaja tal cual (nunca se normaliza), solo se
  /// codifica para la URL.
  Future<Device> getDevice(String deviceUid) async {
    final data = await _client.get(
      '${ApiConfig.devicesPath}/${Uri.encodeComponent(deviceUid)}',
    );
    return Device.fromJson(data as Map<String, dynamic>);
  }

  /// Activa o desactiva el autodescubrimiento en el servidor. Mientras
  /// esta activo, los dispositivos que envien heartbeat sin estar
  /// registrados quedan como pendientes de vinculacion.
  Future<void> setAutoconfigEnabled(bool enabled) async {
    await _client.post(
      '${ApiConfig.devicesPath}/autoconfig',
      body: {'enabled': enabled},
    );
  }

  /// Dispositivos detectados por el autodescubrimiento que aun no
  /// estan registrados.
  ///
  /// Acepta tanto una lista directa como un envoltorio
  /// `{"devices": [...]}` segun la forma exacta del backend.
  Future<List<PendingDevice>> getPendingDevices() async {
    final data = await _client.get(
      '${ApiConfig.devicesPath}/autoconfig/pending',
    );
    final List<dynamic> items;
    if (data is List<dynamic>) {
      items = data;
    } else if (data is Map<String, dynamic> &&
        data['devices'] is List<dynamic>) {
      items = data['devices'] as List<dynamic>;
    } else {
      throw const FormatException(
        'Respuesta inesperada de dispositivos pendientes.',
      );
    }
    return items
        .map((item) => PendingDevice.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Registra un dispositivo en el inventario (configuracion manual o
  /// confirmacion de un dispositivo detectado).
  ///
  /// El contrato actual no exige puerto: se omite por completo.
  Future<Device> registerDevice({
    required String deviceUid,
    required String name,
    required String type,
    String? ipAddress,
    String? macAddress,
  }) async {
    final body = <String, dynamic>{
      'device_uid': deviceUid,
      'name': name,
      'type': type,
      if (ipAddress != null && ipAddress.isNotEmpty) 'ip_address': ipAddress,
      if (macAddress != null && macAddress.isNotEmpty) 'mac_address': macAddress,
    };
    final data = await _client.post(ApiConfig.devicesPath, body: body);
    return Device.fromJson(data as Map<String, dynamic>);
  }

  /// Actualiza datos de registro de un dispositivo existente (PATCH).
  /// El `type` selecciona el controlador de energia del servidor
  /// (google_tv/android_tv -> ADB desde el servidor; otro -> WebSocket).
  Future<Device> updateDevice(
    String deviceUid, {
    String? type,
    String? macAddress,
  }) async {
    final body = <String, dynamic>{
      if (type != null && type.isNotEmpty) 'type': type,
      if (macAddress != null && macAddress.isNotEmpty) 'mac_address': macAddress,
    };
    final data = await _client.patch(
      '${ApiConfig.devicesPath}/${Uri.encodeComponent(deviceUid)}',
      body: body,
    );
    return Device.fromJson(data as Map<String, dynamic>);
  }

  /// Envia un comando de energia al dispositivo.
  ///
  /// [action]: 'on' = encender; 'off' = entrar en espera. El servidor lo
  /// ejecuta con el controlador del tipo del dispositivo (p. ej. ADB
  /// desde el servidor para google_tv/android_tv, usando la IP del
  /// ultimo heartbeat); los tipos sin controlador nativo usan el canal
  /// WebSocket vivo. El resultado trae `method`/`success`/`detail` del
  /// intento; el estado real sigue llegando por heartbeat. Lanza
  /// `ApiException` 409 si el fallback WebSocket no tiene canal abierto,
  /// 504 si el comando excede el tiempo maximo y 403 sin permiso
  /// `devices.control`.
  Future<PowerCommandResult> sendPowerCommand(
    String deviceUid,
    String action,
  ) async {
    final data = await _client.post(
      '${ApiConfig.devicesPath}/${Uri.encodeComponent(deviceUid)}/power',
      body: {'action': action},
    );
    return PowerCommandResult.fromJson(data as Map<String, dynamic>);
  }
}
