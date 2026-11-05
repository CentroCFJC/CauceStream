/// Servicio de autenticacion contra el backend Cauce.
///
/// Contrato real: POST /api/auth/login con {email, password} donde la
/// contrasena es un PIN numerico de 4 digitos. Devuelve
/// {access_token, token_type}. No existe endpoint de logout: la sesion
/// se cierra eliminando el token localmente.
library;

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';

class LoginResult {
  const LoginResult({required this.accessToken, required this.tokenType});

  final String accessToken;
  final String tokenType;
}

class AuthService {
  AuthService({required ApiClient client}) : _client = client;

  /// El login ejecuta verificacion bcrypt en el servidor de la sala;
  /// con el contenedor en arranque en frio o bajo carga puede tardar
  /// bastante mas que una peticion normal, por lo que se permite un
  /// margen mayor al timeout por defecto del cliente.
  static const Duration loginTimeout = Duration(seconds: 60);

  final ApiClient _client;

  /// Intercambia credenciales por un token de acceso firmado.
  ///
  /// Lanza [ApiException] con kind `auth` cuando el correo o el PIN son
  /// invalidos (401) o la cuenta esta desactivada (403), y `network`
  /// cuando el servidor no responde.
  Future<LoginResult> login({
    required String email,
    required String pin,
  }) async {
    final data =
        await _client.post(
              ApiConfig.loginPath,
              body: {'email': email, 'password': pin},
              timeout: loginTimeout,
            )
            as Map<String, dynamic>;

    return LoginResult(
      accessToken: data['access_token'] as String,
      tokenType: data['token_type'] as String? ?? 'bearer',
    );
  }
}
