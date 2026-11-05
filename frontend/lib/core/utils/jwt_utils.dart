/// Decodificacion local del payload de un JWT de Cauce.
///
/// El backend no expone un endpoint `/users/me`, asi que la identidad
/// basica (id de usuario y expiracion) se obtiene del propio token.
/// Solo se decodifica el payload (base64url); la firma no se valida en
/// el cliente: la validez real la determina el servidor en cada peticion.
library;

import 'dart:convert';

class JwtPayload {
  const JwtPayload({required this.subject, this.expiresAt});

  /// `sub`: id del usuario autenticado.
  final int subject;

  /// `exp`: fecha de expiracion en segundos desde la epoca Unix.
  final DateTime? expiresAt;

  bool get isExpired {
    final exp = expiresAt;
    return exp != null && DateTime.now().isAfter(exp);
  }
}

JwtPayload? decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;

  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = utf8.decode(base64.decode(payload));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    final sub = int.tryParse('${map['sub'] ?? ''}');
    if (sub == null) return null;
    final exp = (map['exp'] as num?)?.toInt();
    return JwtPayload(
      subject: sub,
      expiresAt: exp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
    );
  } catch (_) {
    return null;
  }
}
