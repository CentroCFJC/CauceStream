/// Controlador de la biblioteca de medios: unica fuente de verdad
/// compartida por la pestana Biblioteca y las pantallas de registro y
/// detalle.
///
/// Paginacion basica: carga inicial de [pageSize] elementos y
/// "cargar mas" por pagina. Tras subir o eliminar se recarga del
/// servidor (nunca estado optimista).
library;

import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../models/media.dart';
import '../services/media_service.dart';
import '../services/thumbnail_service.dart';

enum MediaLibraryStatus { idle, loading, ready, error }

class MediaLibraryController extends ChangeNotifier {
  MediaLibraryController({
    required MediaService service,
    required ThumbnailService thumbnails,
  }) : _service = service,
       _thumbnails = thumbnails;

  final MediaService _service;

  /// Servicio de medios compartido (subida, registro, borrado).
  MediaService get service => _service;

  /// Miniaturas compartidas (listado y detalle, con caché de disco).
  final ThumbnailService _thumbnails;
  ThumbnailService get thumbnails => _thumbnails;

  /// Tamano de pagina del listado (limite maximo del backend: 200).
  static const int pageSize = 50;

  List<Media> _media = const [];
  List<Media> get media => _media;

  MediaLibraryStatus _status = MediaLibraryStatus.idle;
  MediaLibraryStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _hasMore = false;
  bool get hasMore => _hasMore;

  int _nextOffset = 0;
  bool _fetching = false;

  /// Carga la biblioteca si nunca se ha consultado. Las pantallas lo
  /// llaman al construirse.
  Future<void> ensureLoaded() async {
    if (_fetching || _status != MediaLibraryStatus.idle) return;
    await refresh();
  }

  /// Recarga la primera pagina contra la API. Nunca lanza: los fallos
  /// se exponen en [errorMessage] conservando la lista anterior.
  Future<void> refresh() async {
    if (_fetching) return;
    _fetching = true;
    if (_media.isEmpty) {
      _status = MediaLibraryStatus.loading;
      notifyListeners();
    }
    try {
      final page = await _service.listMedia(limit: pageSize);
      _media = page;
      _nextOffset = page.length;
      _hasMore = page.length == pageSize;
      _errorMessage = null;
      _status = MediaLibraryStatus.ready;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _status = MediaLibraryStatus.error;
    } finally {
      _fetching = false;
      notifyListeners();
    }
  }

  /// Trae la pagina siguiente y la anexa al listado en memoria.
  /// Un fallo temporal deja la lista intacta.
  Future<void> loadMore() async {
    if (_fetching || !_hasMore) return;
    _fetching = true;
    try {
      final page = await _service.listMedia(
        limit: pageSize,
        offset: _nextOffset,
      );
      _media = [..._media, ...page];
      _nextOffset += page.length;
      _hasMore = page.length == pageSize;
      _errorMessage = null;
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } finally {
      _fetching = false;
      notifyListeners();
    }
  }

  /// Elimina un medio en el servidor, limpia sus miniaturas del
  /// caché y recarga la biblioteca. Devuelve false si el backend
  /// rechaza la operacion (el mensaje queda en [errorMessage]).
  Future<bool> remove(Media media) async {
    try {
      await _service.deleteMedia(media.id);
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
    await _thumbnails.removeMedia(media.id);
    await refresh();
    return true;
  }
}
