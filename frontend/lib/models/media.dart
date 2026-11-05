/// Modelos de dominio del frontend.
///
/// `Media` refleja el esquema `MediaRead` del backend
/// (app/schemas/media.py). El nombre es solo display: nunca se usa
/// como ruta; la identidad es el `id`.
library;

import 'package:flutter/material.dart';

import '../core/utils/date_labels.dart';

class Media {
  const Media({
    required this.id,
    required this.name,
    required this.mediaType,
    required this.createdAt,
    required this.updatedAt,
    this.mimeType,
    this.fileSize,
    this.storageKey,
    this.externalUrl,
  });

  final int id;
  final String name;

  /// 'image' | 'video' | 'url'.
  final String mediaType;
  final String? mimeType;

  /// Bytes del archivo; null para medios de tipo url.
  final int? fileSize;

  /// Ruta interna del almacenamiento del servidor (informativa).
  final String? storageKey;

  /// URL externa registrada; solo para mediaType == 'url'.
  final String? externalUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Media.fromJson(Map<String, dynamic> json) => Media(
    id: json['id'] as int,
    name: json['name'] as String,
    mediaType: json['media_type'] as String,
    mimeType: json['mime_type'] as String?,
    fileSize: json['file_size'] as int?,
    storageKey: json['storage_key'] as String?,
    externalUrl: json['external_url'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isUrl => mediaType == 'url';

  /// Medio almacenado en el servidor (con binario descargable).
  bool get isFile => isImage || isVideo;

  String get typeLabel => switch (mediaType) {
    'image' => 'Imagen',
    'video' => 'Video',
    'pdf' => 'PDF',
    _ => 'Enlace',
  };

  IconData get typeIcon => switch (mediaType) {
    'image' => Icons.image,
    'video' => Icons.movie,
    'pdf' => Icons.picture_as_pdf,
    _ => Icons.link,
  };

  /// Icono del medio en reproduccion: triangulo de play para video
  /// (el punto rojo de la sala), icono de tipo para imagen/enlace.
  IconData get playingIcon => isVideo ? Icons.play_arrow : typeIcon;

  /// Tamano legible ('840 KB', '12.5 MB'); null cuando no aplica
  /// (medios de tipo url).
  String? get readableSize {
    final bytes = fileSize;
    if (bytes == null) return null;
    const kb = 1024;
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / gb).toStringAsFixed(1)} GB';
  }

  /// Linea secundaria de las tarjetas: formato y tamano.
  String get subtitle {
    final size = readableSize;
    final parts = <String?>[
      ?mimeType,
      ?size,
    ].whereType<String>().where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? typeLabel : parts.join(' - ');
  }

  /// Fecha de actualizacion en formato local corto.
  String get dateLabel => shortLocalDate(updatedAt);

  /// Jerarquia de datos de la tarjeta del listado: tipo, tamano (o
  /// condicion de recurso externo) y fecha. Solo datos del servidor.
  String get metaLine {
    final sizeOrExternal = readableSize ?? 'Recurso externo';
    return '$typeLabel · $sizeOrExternal · $dateLabel';
  }
}
