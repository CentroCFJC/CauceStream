import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Resuelve el device_uid: el nombre del dispositivo tal como lo expone
/// el sistema operativo, SIN normalizar (el servidor lo acepta tal cual,
/// incluidos espacios; máximo 100 caracteres).
class DeviceIdentity {
  DeviceIdentity._();

  static const MethodChannel _channel = MethodChannel('cauce_stream/device');

  /// Límite que exige el backend en `device_uid`.
  static const int maxDeviceUidLength = 100;

  static Future<String> resolve() async {
    final name = await _rawName();
    if (name.length > maxDeviceUidLength) {
      debugPrint(
        '[CAUCE] Nombre de dispositivo demasiado largo (${name.length} > '
        '$maxDeviceUidLength); se trunca: "$name"',
      );
      return name.substring(0, maxDeviceUidLength);
    }
    return name;
  }

  static Future<String> _rawName() async {
    if (Platform.isWindows) {
      final envName = Platform.environment['COMPUTERNAME'];
      final name = (envName != null && envName.trim().isNotEmpty)
          ? envName
          : Platform.localHostname;
      return name.trim();
    }
    if (Platform.isAndroid) {
      try {
        final name = await _channel.invokeMethod<String>('getDeviceName');
        if (name != null && name.trim().isNotEmpty) return name.trim();
      } on PlatformException catch (e) {
        debugPrint('[CAUCE] No se pudo leer el nombre Android: ${e.message}');
      } on MissingPluginException {
        // Canal no disponible (p. ej. en tests): se devuelve vacío y el
        // heartbeat queda deshabilitado desde main.
      }
      return '';
    }
    return Platform.localHostname.trim();
  }

  /// MAC de la interfaz de red activa, en formato AA:BB:CC:DD:EE:FF.
  ///
  /// La usa el servidor para Wake-on-LAN (app/power del backend).
  /// En Android se lee del canal nativo: WifiManager devuelve
  /// 02:00:00:00:00:00 desde Android 6 por privacidad, así que ahí se
  /// lee de NetworkInterface. En otras plataformas se deriva de
  /// NetworkInterface directamente. null si no se puede determinar.
  static Future<String?> resolveMacAddress() async {
    if (Platform.isAndroid) {
      try {
        final mac = await _channel.invokeMethod<String>('getMacAddress');
        if (mac != null && isValidMac(mac)) return mac.toUpperCase();
      } on PlatformException catch (e) {
        debugPrint('[CAUCE] No se pudo leer la MAC Android: ${e.message}');
      } on MissingPluginException {
        // Canal no disponible (p. ej. en tests).
      }
      return null;
    }
    // dart:io no expone la MAC en otras plataformas: solo Android la
    // reporta (vía canal nativo). En el resto se registra a mano en el
    // servidor o se omite (sin Wake-on-LAN).
    return null;
  }

  static bool isValidMac(String mac) =>
      RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(mac);
}
