/// Almacenamiento persistente de material de sesion.
///
/// El token JWT y el correo recordado se guardan en el almacenamiento
/// seguro del dispositivo (flutter_secure_storage). Nunca se persisten
/// PINs ni contrasenas.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'cauce_access_token';
  static const _emailKey = 'cauce_remembered_email';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<String?> readRememberedEmail() => _storage.read(key: _emailKey);

  Future<void> saveSession({required String token, String? rememberedEmail}) =>
      _storage.write(key: _tokenKey, value: token).then((_) {
        if (rememberedEmail == null || rememberedEmail.isEmpty) {
          return _storage.delete(key: _emailKey);
        }
        return _storage.write(key: _emailKey, value: rememberedEmail);
      });

  /// Cierra la sesion local eliminando el token. El correo recordado
  /// se conserva: es justamente el proposito de "Recordar mi correo".
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
  }
}
