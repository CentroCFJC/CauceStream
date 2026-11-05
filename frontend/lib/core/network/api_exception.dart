/// Excepciones de la capa de red.
///
/// Distinguen claramente tres familias de fallo:
/// 1. Conexion: el servidor no responde (sin red, timeout, DNS).
/// 2. Autenticacion/autorizacion: 401 o 403 devueltos por el backend.
/// 3. Respuesta del servidor: errores 4xx/5xx con cuerpo {code, detail}.
library;

/// Causa general de un fallo de comunicacion con la API.
enum ApiErrorKind {
  /// No hay ruta hasta el servidor (timeout, socket, sin red).
  network,

  /// Credenciales o permisos invalidos (401/403).
  auth,

  /// El servidor respondio con un error de cliente (400, 404, 409...).
  client,

  /// El servidor respondio con un error interno (5xx).
  server,

  /// Formato inesperado de la respuesta.
  parsing,
}

class ApiException implements Exception {
  ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
  });

  final ApiErrorKind kind;
  final String message;

  /// Codigo HTTP de la respuesta, si la hubo.
  final int? statusCode;

  /// Codigo legible por maquina devuelto por el backend ({code, detail}).
  final String? code;

  bool get isAuthError =>
      kind == ApiErrorKind.auth || statusCode == 401 || statusCode == 403;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    final machine = (code == null || code!.isEmpty) ? '' : ' [$code]';
    return '$message$status$machine';
  }
}
