/// Controlador de sesion: unica fuente de verdad del estado de
/// autenticacion de la app.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/utils/jwt_utils.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import 'token_storage.dart';

enum SessionStatus { initializing, authenticated, unauthenticated }

/// Resultado de cargar el perfil desde el backend.
enum ProfileLoadResult {
  /// Se obtuvo el usuario completo (solo posible para ADMINISTRADOR,
  /// que posee `users.view`).
  full,

  /// El backend denego el acceso al detalle (403): perfil de solo
  /// lectura con los datos disponibles localmente (correo + id del token).
  restricted,

  /// Fallo de red al contactar el servidor.
  networkError,
}

class SessionController extends ChangeNotifier {
  SessionController({
    required TokenStorage storage,
    required AuthService authService,
    required UserService userService,
    required ApiClient apiClient,
  }) : _storage = storage,
       _authService = authService,
       _userService = userService,
       _apiClient = apiClient;

  final TokenStorage _storage;
  final AuthService _authService;
  final UserService _userService;
  final ApiClient _apiClient;

  SessionStatus _status = SessionStatus.initializing;
  SessionStatus get status => _status;

  String? _token;
  String? get token => _token;

  /// Correo usado en el ultimo login exitoso (o recordado).
  String? _email;
  String? get email => _email;

  JwtPayload? _payload;
  JwtPayload? get payload => _payload;

  /// Usuario completo cuando el backend lo permite.
  User? _user;
  User? get user => _user;

  /// true cuando el perfil ya se conoce (rol disponible para la UI).
  bool get hasUser => _user != null;

  /// Ultimo error de autenticacion para mostrarlo en el login.
  String? _lastAuthError;
  String? get lastAuthError => _lastAuthError;

  bool get isAdmin => _user?.isAdmin ?? false;

  /// Restaura la sesion guardada al arrancar la aplicacion.
  Future<void> restore() async {
    _status = SessionStatus.initializing;
    notifyListeners();

    final token = await _storage.readToken();
    final remembered = await _storage.readRememberedEmail();
    if (token == null || token.isEmpty) {
      _status = SessionStatus.unauthenticated;
      _email = remembered;
      notifyListeners();
      return;
    }

    final payload = decodeJwtPayload(token);
    if (payload == null || payload.isExpired) {
      // El token caduco: se descarta, pero el correo recordado
      // sobrevive para volver a mostrarlo en el login.
      await _storage.clear();
      _status = SessionStatus.unauthenticated;
      _email = remembered;
      notifyListeners();
      return;
    }

    _token = token;
    _payload = payload;
    _email = remembered;
    _apiClient.accessToken = token;
    _status = SessionStatus.authenticated;
    notifyListeners();

    // Precarga el perfil cuando el backend lo permite (solo
    // ADMINISTRADOR tiene `users.view`): sin ella, la app no conoceria
    // el rol para mostrar/ocultar acciones como la subida de medios
    // hasta visitar el perfil. Para un mediador fallara con 403 y el
    // perfil queda restringido, como si ya se hubiera visitado.
    unawaited(loadProfile());
  }

  /// Inicia sesion contra el backend real.
  ///
  /// Devuelve true en exito. En fallo deja el mensaje en
  /// [lastAuthError] clasificado por tipo (red / credenciales).
  Future<bool> login({
    required String email,
    required String pin,
    bool rememberEmail = false,
  }) async {
    _lastAuthError = null;
    try {
      final result = await _authService.login(email: email, pin: pin);
      final payload = decodeJwtPayload(result.accessToken);
      if (payload == null) {
        _lastAuthError = 'El servidor devolvio un token invalido.';
        notifyListeners();
        return false;
      }
      await _storage.saveSession(
        token: result.accessToken,
        rememberedEmail: rememberEmail ? email : null,
      );
      _token = result.accessToken;
      _payload = payload;
      _email = email;
      _user = null;
      _apiClient.accessToken = result.accessToken;
      _status = SessionStatus.authenticated;
      notifyListeners();

      // Perfil en segundo plano: habilita las capacidades de la UI
      // (subida/eliminacion de medios) sin esperar a la pantalla de
      // perfil.
      unawaited(loadProfile());
      return true;
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.network) {
        _lastAuthError = e.message;
      } else if (e.statusCode == 401) {
        _lastAuthError = 'Correo o PIN incorrectos.';
      } else if (e.statusCode == 403) {
        _lastAuthError =
            'La cuenta esta desactivada. Contacta al administrador.';
      } else {
        _lastAuthError = e.message;
      }
      notifyListeners();
      return false;
    }
  }

  /// Carga el perfil del usuario autenticado.
  ///
  /// El backend no expone `/users/me`: se consulta
  /// GET /api/users/{sub del token}. Solo los administradores tienen
  /// `users.view`; para un mediador el servidor responde 403 y la app
  /// muestra un perfil de solo lectura con los datos locales.
  Future<ProfileLoadResult> loadProfile() async {
    final currentPayload = _payload;
    if (currentPayload == null) return ProfileLoadResult.networkError;
    try {
      final user = await _userService.getUser(currentPayload.subject);
      _user = user;
      notifyListeners();
      return ProfileLoadResult.full;
    } on ApiException catch (e) {
      if (e.isAuthError) {
        // Sin `users.view`: perfil restringido de solo lectura.
        return ProfileLoadResult.restricted;
      }
      return ProfileLoadResult.networkError;
    }
  }

  /// Actualiza los datos editables del usuario autenticado.
  ///
  /// Solo tiene efecto para administradores (el mediador no posee el
  /// permiso de gestion de su propio rol). Devuelve el usuario
  /// actualizado o null si el backend rechazo la operacion.
  Future<User?> updateOwnProfile({
    String? name,
    String? email,
    String? pin,
  }) async {
    final currentPayload = _payload;
    if (currentPayload == null) return null;
    try {
      final updated = await _userService.updateUser(
        currentPayload.subject,
        name: name,
        email: email,
        pin: pin,
      );
      _user = updated;
      if (email != null && email.isNotEmpty) {
        _email = email;
      }
      notifyListeners();
      return updated;
    } on ApiException {
      return null;
    }
  }

  /// Cierra la sesion. No existe endpoint de logout en el backend, asi
  /// que la invalidacion es local: se eliminan token y correo guardados.
  Future<void> logout() async {
    await _storage.clear();
    _token = null;
    _payload = null;
    _user = null;
    _apiClient.accessToken = null;
    _status = SessionStatus.unauthenticated;
    notifyListeners();
  }
}
