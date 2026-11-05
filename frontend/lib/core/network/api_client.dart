/// Cliente HTTP central para la API de Cauce.
///
/// Toda peticion pasa por aqui: se inyecta el token de sesion como
/// `Authorization: Bearer`, se interpreta el formato de errores del
/// backend ({code, detail}) y se clasifica cada fallo en
/// [ApiException]. Nunca se registran tokens ni credenciales en logs.
///
/// Ademas del JSON habitual, cubre las subidas multipart de la
/// biblioteca de medios y las descargas binarias autenticadas (p. ej.
/// la vista previa de una imagen).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client, required this.baseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  String? accessToken;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (accessToken != null && accessToken!.isNotEmpty)
      'Authorization': 'Bearer $accessToken',
  };

  /// Tiempo de espera por defecto para las peticiones. El backend corre
  /// en el hardware de la sala (Docker sobre el nodo central), donde las
  /// operaciones con bcrypt o con el arranque en frio pueden tardar
  /// varios segundos; por eso el margen es generoso.
  static const Duration defaultTimeout = Duration(seconds: 20);

  /// Margen para subidas multipart: los archivos de medios viajan
  /// completos por la LAN (limite del servidor: 200 MB) y un envio
  /// grande tarda mas que una peticion JSON normal.
  static const Duration uploadTimeout = Duration(seconds: 120);

  Uri _uri(String path, [Map<String, String>? query]) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(
      '$cleanBase$cleanPath',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  /// Ejecuta una peticion y devuelve el cuerpo JSON decodificado
  /// (o null cuando la respuesta viene vacia, p. ej. 204).
  ///
  /// [timeout] permite alargar la espera para operaciones costosas
  /// (p. ej. el login, que ejecuta bcrypt en el servidor).
  Future<dynamic> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final uri = _uri(path, query);
    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? defaultTimeout);
    } on TimeoutException {
      throw ApiException(
        kind: ApiErrorKind.network,
        message: 'El servidor Cauce no responde (tiempo de espera agotado).',
      );
    } catch (_) {
      throw ApiException(
        kind: ApiErrorKind.network,
        message:
            'No hay conexion con el servidor Cauce. Verifica la red de la sala.',
      );
    }

    return _decode(response);
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) => send('GET', path, query: query, timeout: timeout);

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) => send('POST', path, body: body, timeout: timeout);

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) =>
      send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) =>
      send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => send('DELETE', path);

  /// Subida multipart (archivos de la biblioteca de medios).
  ///
  /// Adjunta el token, envia los campos de formulario y el archivo, y
  /// clasifica la respuesta con el mismo [_decode] que el resto de
  /// peticiones. El Content-Type lo fija MultipartRequest (boundary):
  /// nunca se declara a mano.
  ///
  /// [onProgress] recibe (bytes enviados, total) mientras el cuerpo
  /// viaja por la LAN: la UI de subida lo usa para su barra de
  /// progreso.
  Future<dynamic> postMultipart(
    String path, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
    Duration? timeout,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = _uri(path);
    http.Response response;
    try {
      final request = _CountingMultipartRequest('POST', uri, onProgress)
        ..headers['Accept'] = 'application/json'
        ..fields.addAll(fields)
        ..files.addAll(files);
      final token = accessToken;
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? uploadTimeout);
    } on TimeoutException {
      throw ApiException(
        kind: ApiErrorKind.network,
        message:
            'La subida tardó demasiado y se cancelo (servidor sin respuesta).',
      );
    } catch (_) {
      throw ApiException(
        kind: ApiErrorKind.network,
        message:
            'No hay conexion con el servidor Cauce. Verifica la red de la sala.',
      );
    }
    return _decode(response);
  }

  /// Descarga binaria autenticada (p. ej. el archivo de un medio para
  /// su vista previa). Devuelve los bytes; los fallos se clasifican
  /// con [_decode].
  Future<Uint8List> getBytes(String path, {Duration? timeout}) async {
    final uri = _uri(path);
    http.Response response;
    try {
      final request = http.Request('GET', uri)..headers.addAll(_headers);
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? defaultTimeout);
    } on TimeoutException {
      throw ApiException(
        kind: ApiErrorKind.network,
        message: 'El servidor Cauce no responde (tiempo de espera agotado).',
      );
    } catch (_) {
      throw ApiException(
        kind: ApiErrorKind.network,
        message:
            'No hay conexion con el servidor Cauce. Verifica la red de la sala.',
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    _decode(response);
    throw StateError('unreachable: _decode siempre lanza en error');
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final raw = response.body;
      if (raw.isEmpty) return null;
      return jsonDecode(raw);
    }

    String detail = 'Error inesperado del servidor.';
    String? code;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        detail = (decoded['detail'] as String?) ?? detail;
        code = decoded['code'] as String?;
      }
    } catch (_) {
      // El cuerpo no es JSON: se conserva el mensaje generico.
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(
        kind: ApiErrorKind.auth,
        message: detail,
        statusCode: response.statusCode,
        code: code,
      );
    }
    if (response.statusCode == 413) {
      // Tamano de subida: usa el detail del backend y, si viene sin
      // cuerpo util, un mensaje claro de tamano.
      final generic = detail == 'Error inesperado del servidor.';
      throw ApiException(
        kind: ApiErrorKind.client,
        message: generic
            ? 'El archivo supera el tamano maximo permitido por el servidor.'
            : detail,
        statusCode: 413,
        code: code ?? 'payload_too_large',
      );
    }
    if (response.statusCode >= 500) {
      throw ApiException(
        kind: ApiErrorKind.server,
        message: detail,
        statusCode: response.statusCode,
        code: code,
      );
    }
    throw ApiException(
      kind: ApiErrorKind.client,
      message: detail,
      statusCode: response.statusCode,
      code: code,
    );
  }
}

/// MultipartRequest que reporta el avance del envio: envuelve el
/// stream del cuerpo con un contador de bytes. No altera el cuerpo.
class _CountingMultipartRequest extends http.MultipartRequest {
  _CountingMultipartRequest(super.method, super.url, this.onProgress);

  final void Function(int sent, int total)? onProgress;

  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final callback = onProgress;
    if (callback == null) return stream;
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(
      stream.map((chunk) {
        sent += chunk.length;
        callback(sent, total);
        return chunk;
      }),
    );
  }
}
