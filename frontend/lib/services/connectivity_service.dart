/// Comprobacion de conectividad con el servidor Cauce.
///
/// Una unica peticion HTTP al endpoint de salud del backend
/// (`GET /api/health`, respuesta `{"status": "ok"}`): la API
/// respondiendo es la prueba real de que la LAN sirve. Nunca se usa
/// ping ICMP: no garantiza que la API este operativa y el firewall
/// puede bloquearlo. Toda la configuracion (URL activa y timeout)
/// vive en [ApiConfig].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';

class ConnectivityService {
  ConnectivityService({
    http.Client? client,
    String? serverUrl,
    Duration? timeout,
  }) : _client = client ?? http.Client(),
       timeout = timeout ?? ApiConfig.connectivityTimeout,
       healthUrl =
           '${serverUrl ?? ApiConfig.activeServerUrl}/api${ApiConfig.healthPath}';

  final http.Client _client;

  /// Endpoint de salud contra el que se comprueba la LAN.
  final String healthUrl;

  /// Espera maxima por comprobacion.
  final Duration timeout;

  /// true solo si el backend respondio HTTP 200 con el cuerpo del
  /// contrato (`status: ok`). Timeout, error de red o respuesta
  /// invalida devuelven false.
  Future<bool> check() async {
    try {
      final response = await _client.get(Uri.parse(healthUrl)).timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint(
          '[Cauce] health $healthUrl respondio HTTP ${response.statusCode}',
        );
        return false;
      }
      final dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        debugPrint('[Cauce] health $healthUrl body no-JSON: ${response.body}');
        return false;
      }
      if (body is! Map || body['status'] != 'ok') {
        debugPrint(
          '[Cauce] health $healthUrl contrato incumplido: ${response.body}',
        );
        return false;
      }
      return true;
    } on Exception catch (e) {
      // El motivo del fallo queda en el log (adb logcat / flutter logs):
      // distingue "no hay ruta al servidor" de "respondio con error".
      debugPrint('[Cauce] health $healthUrl fallo de red: $e');
      return false;
    } catch (e) {
      debugPrint('[Cauce] health $healthUrl fallo inesperado: $e');
      return false;
    }
  }
}
