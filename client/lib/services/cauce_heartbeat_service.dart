import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'device_identity.dart';
import 'playback_state.dart';

/// Envía heartbeats periódicos al servidor Cauce (protocolo de
/// dispositivos, sin autenticación de usuario).
///
/// El device_uid es el nombre del dispositivo tal como lo expone el SO,
/// sin normalizar; va URL-encoded en la ruta. El device_state se deriva
/// del ciclo de vida de la app (resumed -> active; cualquier otro estado
/// -> idle) y `status` (conectividad) NUNCA se reporta: lo determina el
/// servidor.
///
/// El medio en reproducción se reporta en `payload.current_media`
/// (Media.id entero), leído del [PlaybackState] compartido: solo el
/// reproductor confirma qué está realmente en pantalla. Sin medio
/// confirmado el campo se OMITE y el servidor guarda "unknown".
/// El retirado `current_application` ya no se envía: el backend lo
/// trató siempre como atributo inerte.
class CauceHeartbeatService with WidgetsBindingObserver {
  CauceHeartbeatService({
    required this.baseUrl,
    required this.deviceUid,
    this.deviceKey,
    this.playbackState,
    http.Client? client,
    Duration interval = const Duration(seconds: 10),
    Duration timeout = const Duration(seconds: 5),
    Future<String> Function()? resolveIpAddress,
    Future<String?> Function()? resolveMacAddress,
  })  : _client = client ?? http.Client(),
        _interval = interval,
        _timeout = timeout,
        _resolveIpAddress = resolveIpAddress ?? _localIPv4Address,
        _resolveMacAddress = resolveMacAddress ?? DeviceIdentity.resolveMacAddress;

  /// URL base del servidor (p. ej. http://10.15.1.150:8000).
  final String baseUrl;

  /// Nombre del dispositivo tal como lo expone el SO (sin normalizar).
  final String deviceUid;

  /// Secreto compartido con el servidor (X-Device-Key). null cuando el
  /// servidor no lo exige (modo transición).
  final String? deviceKey;

  /// Fuente compartida del medio confirmado en pantalla. null en
  /// pruebas aisladas del heartbeat.
  final PlaybackState? playbackState;

  final http.Client _client;
  final Duration _interval;
  final Duration _timeout;
  final Future<String> Function() _resolveIpAddress;
  final Future<String?> Function() _resolveMacAddress;

  /// MAC resuelta una sola vez (la interfaz no cambia en operación);
  /// null si no se pudo determinar: entonces simplemente no se envía.
  String? _macAddress;
  bool _macResolved = false;

  Timer? _timer;
  bool _sending = false;
  bool _disposed = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  // Log de advertencias de solo una vez hasta que un heartbeat tenga
  // éxito, para no spamear mientras el servidor está caído.
  bool _warnedUnregistered = false;
  bool _warnedPendingRegistration = false;
  bool _warnedFailure = false;

  bool get isRunning => _timer != null;

  /// `active` con la app en primer plano; `idle` en cualquier otro
  /// estado del ciclo de vida (sigue enviando heartbeats: es estado
  /// operativo, no conectividad).
  String get deviceState =>
      _lifecycle == AppLifecycleState.resumed ? 'active' : 'idle';

  void start() {
    if (_disposed || isRunning) return;
    debugPrint(
      '[CAUCE] Heartbeat iniciado (device_uid="$deviceUid", '
      'server=$baseUrl, cada ${_interval.inSeconds}s)',
    );
    WidgetsBinding.instance.addObserver(this);
    _scheduleNext();
  }

  /// Detiene el temporizador pero permite reiniciar (p. ej. tras un 422
  /// se detiene para no reintentar en bucle con el mismo payload).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    WidgetsBinding.instance.removeObserver(this);
    _client.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // Al volver a primer plano se envía de inmediato para que el
    // servidor detecte la recuperación rápido (offline -> online).
    if (state == AppLifecycleState.resumed && isRunning) {
      unawaited(sendHeartbeat());
    }
  }

  void _scheduleNext() {
    if (_disposed) return;
    _timer = Timer(_interval + _jitter(), _tick);
  }

  Duration _jitter() =>
      Duration(milliseconds: Random().nextInt(2000) - 1000);

  Future<void> _tick() async {
    if (_disposed || !isRunning) return;
    await sendHeartbeat();
    // sendHeartbeat puede llamar a stop() (422): no reprogramar en ese caso.
    if (_disposed || !isRunning) return;
    _scheduleNext();
  }

  /// Envía un heartbeat individual. Nunca lanza: los fallos se loguean
  /// y el siguiente ciclo reintenta.
  Future<void> sendHeartbeat() async {
    if (_disposed || _sending) return;
    _sending = true;
    try {
      final ipAddress = await _resolveIpAddress();
      // La MAC se resuelve una sola vez y se reporta como campo general
      // (igual que la IP): el servidor la usa para Wake-on-LAN.
      if (!_macResolved) {
        _macAddress = await _resolveMacAddress();
        _macResolved = true;
      }
      final macAddress = _macAddress;
      // `current_media` solo va cuando el reproductor confirmó el
      // medio: el Media.id entero del contrato. Sin medio confirmado
      // se omite y el servidor guarda "unknown".
      final mediaId = playbackState?.currentMediaId;
      final body = jsonEncode({
        'ip_address': ipAddress,
        if (macAddress != null) 'mac_address': macAddress,
        'device_state': deviceState,
        'payload': {
          if (mediaId != null) 'current_media': mediaId,
        },
      });
      final uri = Uri.parse(
        '$baseUrl/api/devices/${Uri.encodeComponent(deviceUid)}/heartbeat',
      );
      final key = deviceKey;
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (key != null) 'X-Device-Key': key,
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        _warnedUnregistered = false;
        _warnedPendingRegistration = false;
        _warnedFailure = false;
      } else if (response.statusCode == 202) {
        // Autoconfig activo: aceptado como descubrimiento pendiente de
        // registro; se sigue latiendo con normalidad.
        if (!_warnedPendingRegistration) {
          _warnedPendingRegistration = true;
          debugPrint(
            '[CAUCE] Heartbeat 202: "$deviceUid" aceptado en espera de '
            'registro (autoconfig activo en el servidor)',
          );
        }
      } else if (response.statusCode == 404) {
        if (!_warnedUnregistered) {
          _warnedUnregistered = true;
          debugPrint(
            '[CAUCE] Heartbeat 404: "$deviceUid" aún no está registrado '
            'en el servidor (autoconfig pendiente); se reintenta cada '
            '${_interval.inSeconds}s',
          );
        }
      } else if (response.statusCode == 422) {
        debugPrint(
          '[CAUCE] Heartbeat 422: payload rechazado por el servidor, se '
          'detiene el servicio hasta corregir: ${response.body}',
        );
        stop();
      } else {
        _warnFailure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _warnFailure('$e');
    } finally {
      _sending = false;
    }
  }

  void _warnFailure(String detail) {
    if (!_warnedFailure) {
      _warnedFailure = true;
      debugPrint(
        '[CAUCE] Heartbeat falló (servidor no disponible), se reintenta '
        'cada ${_interval.inSeconds}s: $detail',
      );
    }
  }

  /// IP LAN propia del dispositivo (IPv4 no loopback). La IP no es la
  /// identidad: solo información de conexión que el dispositivo declara.
  static Future<String> _localIPv4Address() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
      // Fallback documentado: sin IPv4 LAN, loopback como último recurso.
      return InternetAddress.loopbackIPv4.address;
    } catch (e) {
      debugPrint('[CAUCE] No se pudo determinar la IP local: $e');
      return InternetAddress.loopbackIPv4.address;
    }
  }
}
