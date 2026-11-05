/// Configuracion central del acceso al servidor Cauce.
///
/// Un unico lugar decide a que direccion se conecta la app: la URL
/// local del servidor de la sala o, cuando la sala la configure, la
/// URL de Tailscale. Ninguna direccion se escribe suelta por el
/// codigo; todo deriva de aqui.
///
/// Sobrescribible en tiempo de compilacion con:
///   flutter run --dart-define=CAUCE_SERVER_LOCAL_URL=http://10.15.1.150:8000
///   flutter run --dart-define=CAUCE_SERVER_TAILSCALE_URL=http://100.x.y.z:8000
library;

import 'dart:core';

class ApiConfig {
  const ApiConfig._();

  /// URL del servidor local de la sala (raiz del backend, sin /api).
  static const String serverLocalUrl = String.fromEnvironment(
    'CAUCE_SERVER_LOCAL_URL',
    defaultValue: 'http://10.15.1.150:8000',
  );

  /// URL del servidor por Tailscale: vacia hasta que la sala la
  /// configure. Mientras este vacia NO se utiliza; no se inventa.
  static const String serverTailscaleUrl = String.fromEnvironment(
    'CAUCE_SERVER_TAILSCALE_URL',
    defaultValue: '',
  );

  /// Direccion activa del servidor: Tailscale si esta configurada,
  /// local en caso contrario. No hay conmutacion automatica entre
  /// ambas: cambiarla es una decision de configuracion, no de
  /// runtime.
  static String get activeServerUrl =>
      serverTailscaleUrl.trim().isEmpty ? serverLocalUrl : serverTailscaleUrl;

  /// URL base de la API: siempre deriva de la direccion activa.
  static String get apiBaseUrl => '$activeServerUrl/api';

  /// Prefijo de red de la sala, informativo.
  static const String lanSubnet = '10.15.0.0/16';

  // --- Sondeo de conectividad (indicador LAN) ---

  static const int _connectivityCheckIntervalSeconds = int.fromEnvironment(
    'CAUCE_CONNECTIVITY_CHECK_INTERVAL',
    defaultValue: 15,
  );

  static const int _connectivityTimeoutSeconds = int.fromEnvironment(
    'CAUCE_CONNECTIVITY_TIMEOUT',
    defaultValue: 5,
  );

  /// Intervalo entre comprobaciones de conectividad con el servidor.
  static Duration get connectivityCheckInterval =>
      Duration(seconds: _connectivityCheckIntervalSeconds);

  /// Espera maxima por comprobacion de salud: una peticion colgada
  /// nunca deja el indicador en comprobacion indefinida.
  static Duration get connectivityTimeout =>
      Duration(seconds: _connectivityTimeoutSeconds);

  // --- Rutas de la API ---

  static const String healthPath = '/health';
  static const String loginPath = '/auth/login';
  static const String usersPath = '/users';
  static const String devicesPath = '/devices';
  static const String assignmentsPath = '/assignments';
  static const String mediaPath = '/media';

  /// Endpoint TEMPORAL de encendido/apagado maestro de la sala
  /// (/room/power). Ver backend/docs/room_power_temporal.md: se
  /// reemplazara por el control maestro individualizado.
  static const String roomPowerPath = '/room';
}
