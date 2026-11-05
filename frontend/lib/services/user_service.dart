/// Servicio de usuarios contra el backend Cauce.
///
/// Contratos reales usados por el perfil:
/// - GET  /api/users/{id}  (requiere permiso `users.view`: solo ADMINISTRADOR)
/// - PATCH /api/users/{id} (requiere el permiso de gestion del rol objetivo;
///   un mediador no puede autoeditarse, un administrador si).
library;

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../models/user.dart';

class UserService {
  UserService({required ApiClient client}) : _client = client;

  final ApiClient _client;

  /// Obtiene un usuario por id. Con un token de mediador el servidor
  /// responde 403 (permiso `users.view` insuficiente).
  Future<User> getUser(int id) async {
    final data = await _client.get('${ApiConfig.usersPath}/$id');
    return User.fromJson(data as Map<String, dynamic>);
  }

  /// Actualiza nombre, correo y/o PIN de un usuario.
  Future<User> updateUser(
    int id, {
    String? name,
    String? email,
    String? pin,
  }) async {
    final body = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (pin != null && pin.isNotEmpty) 'password': pin,
    };
    final data = await _client.patch('${ApiConfig.usersPath}/$id', body: body);
    return User.fromJson(data as Map<String, dynamic>);
  }
}
