/// Ejecutor de pantalla para los comandos de energía (`power.command`).
///
/// Interfaz inyectable (como `CauceSocketConnector`): el servicio de
/// socket nunca depende de platform channels en pruebas. La
/// implementación de producción (`MethodChannelPowerExecutor`) habla
/// con el lado nativo por el canal `cauce.power/power`.
///
/// Contrato:
/// - `Future<bool>`: true = acción aplicada (idempotente: aplicar "on"
///   con la pantalla ya encendida es éxito, no error); false = la
///   plataforma no permite la acción (p. ej. `enterStandby` en Android
///   sin la app aprovisionada como Device Owner / Device Admin).
/// - Puede lanzar [PowerExecutorException] con un código estable de
///   `PowerErrorCodes` cuando el fallo es distinguible (plataforma sin
///   implementación del canal, error nativo).
library;

import 'package:cauce_stream/models/playback_message.dart';
import 'package:flutter/services.dart';

abstract class PowerExecutor {
  const PowerExecutor();

  /// Entrar en espera (action "off"): apagar la pantalla. El
  /// dispositivo NO se apaga; la app sigue corriendo (heartbeats).
  Future<bool> enterStandby();

  /// Salir de espera (action "on"): encender la pantalla.
  Future<bool> wakeScreen();

  /// Capacidades reales de energía de la plataforma: diagnóstico y para
  /// saber si falta aprovisionar Device Owner antes de poder apagar.
  Future<PowerCapabilities> capabilities();

  /// Pide activar la app como administradora de dispositivo (Device
  /// Admin clásico, diálogo del sistema). true si ya estaba activa o el
  /// flujo se lanzó. Device Owner requiere aprovisionamiento por ADB/QR
  /// (ver client/docs/device_owner_setup.md).
  Future<bool> requestDeviceAdmin();
}

/// Capacidades de energía que reporta la plataforma nativa
/// (`getPowerCapabilities` del canal `cauce.power/power`).
class PowerCapabilities {
  const PowerCapabilities({
    required this.canWake,
    required this.canStandby,
    required this.deviceOwner,
    required this.adminActive,
  });

  /// Encender la pantalla: soportado sin aprovisionamiento (wake lock
  /// con ACQUIRE_CAUSES_WAKEUP en Android).
  final bool canWake;

  /// Apagar la pantalla: solo con Device Owner o Device Admin activo.
  final bool canStandby;

  final bool deviceOwner;
  final bool adminActive;

  factory PowerCapabilities.fromMap(Map<dynamic, dynamic> map) {
    return PowerCapabilities(
      canWake: map['can_wake'] == true,
      canStandby: map['can_standby'] == true,
      deviceOwner: map['device_owner'] == true,
      adminActive: map['admin_active'] == true,
    );
  }
}

/// Fallo distinguible del ejecutor con un código estable del contrato
/// (`PowerErrorCodes`); viaja tal cual en `power.error`.
class PowerExecutorException implements Exception {
  const PowerExecutorException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'PowerExecutorException($code): $message';
}

/// Implementación de producción: MethodChannel `cauce.power/power`.
///
/// Android: `wakeScreen` enciende la pantalla con wake lock
/// ACQUIRE_CAUSES_WAKEUP (API pública, permiso normal WAKE_LOCK).
/// `enterStandby` apaga la pantalla invocando por reflexión el
/// DevicePolicyManager.goToSleep() oculto (@hide) del framework, que solo
/// acepta la llamada cuando la app está aprovisionada como Device Owner /
/// Device Admin; sin aprovisionamiento devuelve false y el cliente
/// responde power.error/standby_denied. Otras plataformas sin handler
/// nativo → `PowerErrorCodes.platformUnsupported`.
class MethodChannelPowerExecutor implements PowerExecutor {
  const MethodChannelPowerExecutor();

  static const MethodChannel _channel = MethodChannel('cauce.power/power');

  @override
  Future<bool> enterStandby() => _invokeBool('enterStandby');

  @override
  Future<bool> wakeScreen() => _invokeBool('wakeScreen');

  @override
  Future<bool> requestDeviceAdmin() => _invokeBool('requestDeviceAdmin');

  @override
  Future<PowerCapabilities> capabilities() async {
    final result = await _invokeRaw('getPowerCapabilities');
    if (result is! Map) {
      throw const PowerExecutorException(
        PowerErrorCodes.platformUnsupported,
        'la plataforma no devolvió las capacidades de energía',
      );
    }
    return PowerCapabilities.fromMap(result);
  }

  Future<bool> _invokeBool(String method) async =>
      await _invokeRaw(method) == true;

  Future<Object?> _invokeRaw(String method) async {
    try {
      return await _channel.invokeMethod<dynamic>(method);
    } on MissingPluginException {
      throw const PowerExecutorException(
        PowerErrorCodes.platformUnsupported,
        'la plataforma no implementa el canal de energía',
      );
    } on PlatformException catch (e) {
      if (e.code == 'unimplemented' || e.code.isEmpty) {
        throw const PowerExecutorException(
          PowerErrorCodes.platformUnsupported,
          'la plataforma no implementa el canal de energía',
        );
      }
      throw PowerExecutorException(
        e.code.length <= 50 ? e.code : PowerErrorCodes.internalError,
        e.message ?? 'error nativo ejecutando $method',
      );
    }
  }
}
