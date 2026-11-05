/// Modelos de dominio del frontend.
///
/// `User` refleja el esquema `UserRead` del backend
/// (app/schemas/user.py). Nunca incluye el hash de contrasena.
library;

class RoleBrief {
  const RoleBrief({required this.id, required this.name, this.description});

  final int id;
  final String name;
  final String? description;

  factory RoleBrief.fromJson(Map<String, dynamic> json) => RoleBrief(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
  );
}

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String email;
  final RoleBrief role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAdmin => role.name == 'ADMINISTRADOR';

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    name: json['name'] as String,
    email: json['email'] as String,
    role: RoleBrief.fromJson(json['role'] as Map<String, dynamic>),
    isActive: json['is_active'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
