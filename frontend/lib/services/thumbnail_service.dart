/// Miniaturas de la biblioteca de medios.
///
/// Solo para imagenes: baja el binario por
/// `GET /api/media/{id}/file` (Authorization incluido, patron
/// `MediaService.getMediaFileBytes`), lo reescala a resolucion de
/// miniatura (nunca sostiene el original en memoria) y lo guarda en
/// un caché de disco **acotado** con eviction LRU.
///
/// - **Clave de invalidacion**: `id + updated_at` (y tamano). Si el
///   medio se reemplaza, cambia su `updated_at` y la clave nueva
///   fuerza una descarga fresca; la entrada antigua caera por LRU.
/// - **Videos**: el backend no genera miniaturas (no existe el
///   endpoint): `thumbnail` devuelve null y la UI muestra el lienzo
///   con el icono de tipo. No se descarga el video para fabricarla.
/// - **URLs**: recursos externos, sin binario: null.
///
/// Cualquier fallo (red, decodificacion, disco) devuelve null: la
/// tarjeta cae al lienzo de tipo sin bloquear el listado.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../models/media.dart';
import 'media_service.dart';

/// Resolucion maxima (px) por destino de la miniatura.
enum ThumbnailSize {
  /// Tarjeta del listado (~128 dp de alto).
  card(400),

  /// Vista previa del detalle (16:9 a lo ancho del telefono).
  detail(1080);

  const ThumbnailSize(this.maxDimension);
  final int maxDimension;
}

class ThumbnailService {
  ThumbnailService({
    required MediaService service,
    Directory? cacheDirectory,
    this.memoryMaxEntries = 64,
    this.memoryMaxBytes = 8 * 1024 * 1024,
    this.diskMaxEntries = 100,
    this.diskMaxBytes = 16 * 1024 * 1024,
  }) : _service = service,
       _cacheDirectory = cacheDirectory;

  final MediaService _service;

  /// Directorio de disco inyectable (tests y plataformas con otro
  /// layout). En produccion se resuelve a
  /// `<cache>/cauce_media_thumbnails` via path_provider.
  final Directory? _cacheDirectory;

  /// Limites del caché: nunca crece sin control.
  final int memoryMaxEntries;
  final int memoryMaxBytes;
  final int diskMaxEntries;
  final int diskMaxBytes;

  Directory? _dir;
  final Map<String, _DiskEntry> _index = {};
  bool _indexLoaded = false;

  /// LRU en memoria de bytes de miniatura (orden de insercion).
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  int _memoryBytes = 0;

  /// Miniaturas en vuelo: deduplica descargas de la misma clave.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static String _key(Media media, ThumbnailSize size) =>
      '${size.name}_${media.id}_${media.updatedAt.millisecondsSinceEpoch}';

  /// Miniatura del medio o null (video/url/fallo). Idempotente y
  /// deduplicada por clave.
  Future<Uint8List?> thumbnail(
    Media media, {
    ThumbnailSize size = ThumbnailSize.card,
  }) async {
    if (!media.isImage) return null;
    final key = _key(media, size);

    final cached = _memory[key];
    if (cached != null) {
      // Refresco de recencia (LRU: reinsertar al final).
      _memory.remove(key);
      _memory[key] = cached;
      return cached;
    }

    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    late final Future<Uint8List?> future;
    future = _load(media, key, size).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<Uint8List?> _load(Media media, String key, ThumbnailSize size) async {
    try {
      await _ensureReady();
    } catch (_) {
      // Sin directorio de cache disponible: se puede generar la
      // miniatura igualmente (solo memoria).
    }

    final entry = _index[key];
    if (entry != null) {
      try {
        final bytes = await entry.file.readAsBytes();
        entry.access = _nowMs();
        _remember(key, bytes);
        return bytes;
      } catch (_) {
        _index.remove(key); // archivo roto o borrado
      }
    }

    try {
      final original = await _service.getMediaFileBytes(media);
      final thumb = await _resize(original, size.maxDimension);
      await _store(key, media.id, thumb);
      _remember(key, thumb);
      return thumb;
    } catch (_) {
      return null; // red, decodificacion o disco: la UI cae al lienzo.
    }
  }

  /// Reduce la imagen (en el hilo de UI de Flutter) al maximo
  /// [maxDimension] conservando el aspecto y la re-encodifica como
  /// PNG: son miniaturas, no el archivo original.
  Future<Uint8List> _resize(Uint8List bytes, int maxDimension) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;

    var targetWidth = width;
    var targetHeight = height;
    final largest = math.max(width, height);
    if (largest > maxDimension) {
      final scale = maxDimension / largest;
      targetWidth = math.max(1, (width * scale).round());
      targetHeight = math.max(1, (height * scale).round());
    }

    final codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes == 0) {
        throw const _ThumbnailException('La imagen no pudo re-encodificarse.');
      }
      return data.buffer.asUint8List();
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  }

  void _remember(String key, Uint8List bytes) {
    final previous = _memory.remove(key);
    if (previous != null) _memoryBytes -= previous.length;
    _memory[key] = bytes;
    _memoryBytes += bytes.length;

    while (_memory.length > memoryMaxEntries ||
        (_memoryBytes > memoryMaxBytes && _memory.length > 1)) {
      final eldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(eldest)!.length;
    }
  }

  Future<void> _ensureReady() async {
    if (_indexLoaded) return;
    final dir = await _resolveDir();
    final indexFile = File('${dir.path}${Platform.pathSeparator}index.json');
    if (await indexFile.exists()) {
      try {
        final raw = jsonDecode(await indexFile.readAsString());
        if (raw is Map<String, dynamic>) {
          final entries = raw['entries'];
          if (entries is Map<String, dynamic>) {
            for (final item in entries.values) {
              final entry = _DiskEntry.fromJson(dir, item);
              if (entry != null) _index[entry.key] = entry;
            }
          }
        }
      } catch (_) {
        // Indice corrupto: se reconstruye desde cero.
        _index.clear();
      }
    }
    _indexLoaded = true;
  }

  Future<Directory> _resolveDir() async {
    final injected = _cacheDirectory;
    if (injected != null) return injected;
    return _dir ??= Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}cauce_media_thumbnails',
    );
  }

  Future<void> _store(String key, int mediaId, Uint8List bytes) async {
    try {
      final dir = await _resolveDir();
      if (!await dir.exists()) await dir.create(recursive: true);

      final file = File('${dir.path}${Platform.pathSeparator}$key.png');
      // Escritura atomica (.part + rename): sin miniaturas parciales.
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      if (await file.exists()) await file.delete();
      await part.rename(file.path);

      _index[key] = _DiskEntry(
        key: key,
        file: file,
        bytes: bytes.length,
        access: _nowMs(),
        mediaId: mediaId,
      );
      await _evict(dir);
      await _saveIndex(dir);
    } catch (_) {
      // Disco lleno o sin permisos: la miniatura vive en memoria y
      // la eviction se ocupa del resto.
    }
  }

  Future<void> _evict(Directory dir) async {
    var total = _index.values.map((e) => e.bytes).fold(0, (a, b) => a + b);
    while (_index.length > diskMaxEntries ||
        (total > diskMaxBytes && _index.length > 1)) {
      _DiskEntry oldest;
      try {
        oldest = _index.values.reduce((a, b) => a.access <= b.access ? a : b);
      } on StateError {
        break;
      }
      _index.remove(oldest.key);
      total -= oldest.bytes;
      _memory.remove(oldest.key);
      try {
        if (await oldest.file.exists()) await oldest.file.delete();
      } catch (_) {
        // El eviction no puede fallar por un archivo bloqueado.
      }
    }
  }

  Future<void> _saveIndex(Directory dir) async {
    final payload = jsonEncode({
      'version': 1,
      'entries': {for (final entry in _index.values) entry.key: entry.toJson()},
    });
    final indexFile = File('${dir.path}${Platform.pathSeparator}index.json');
    final part = File('${indexFile.path}.part');
    await part.writeAsString(payload, flush: true);
    if (await indexFile.exists()) await indexFile.delete();
    await part.rename(indexFile.path);
  }

  /// Limpia las entradas de un medio eliminado del servidor (evita
  /// huerfanos en disco).
  Future<void> removeMedia(int mediaId) async {
    final stale = _index.values.where((e) => e.mediaId == mediaId).toList();
    for (final entry in stale) {
      _index.remove(entry.key);
      final bytes = _memory.remove(entry.key);
      if (bytes != null) _memoryBytes -= bytes.length;
      try {
        if (await entry.file.exists()) await entry.file.delete();
      } catch (_) {
        // Un archivo bloqueado se ira en la siguiente eviction.
      }
    }
    if (stale.isEmpty || _dir == null && _cacheDirectory == null) return;
    try {
      await _ensureReady();
      final dir = await _resolveDir();
      await _saveIndex(dir);
    } catch (_) {
      // Sin disco disponible: la limpieza en memoria ya ocurrio.
    }
  }
}

class _DiskEntry {
  _DiskEntry({
    required this.key,
    required this.file,
    required this.bytes,
    required this.access,
    required this.mediaId,
  });

  final String key;
  final File file;
  final int bytes;
  int access;
  final int mediaId;

  static _DiskEntry? fromJson(Directory dir, dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final key = json['key'] as String?;
    final fileName = json['file'] as String?;
    if (key == null || fileName == null) return null;
    return _DiskEntry(
      key: key,
      file: File('${dir.path}${Platform.pathSeparator}$fileName'),
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      access: (json['access'] as num?)?.toInt() ?? 0,
      mediaId: (json['mediaId'] as num?)?.toInt() ?? -1,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'file': file.uri.pathSegments.last,
    'bytes': bytes,
    'access': access,
    'mediaId': mediaId,
  };
}

class _ThumbnailException implements Exception {
  const _ThumbnailException(this.message);
  final String message;

  @override
  String toString() => message;
}
