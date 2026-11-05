import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/io.dart';

import '../models/playback_message.dart';
import 'cauce_media_downloader.dart';
import 'playback_state.dart';
import 'power_executor.dart';

/// Conexión mínima que el servicio necesita de un WebSocket. Propia y
/// delgada para poder probar todo el ciclo con canales falsos sin
/// depender de sockets reales.
abstract class CauceSocket {
  Stream get stream;

  void add(String data);

  Future<void> close();
}

/// Fábrica de conexión inyectable. La de producción usa
/// `IOWebSocketChannel.connect` con el header del handshake.
typedef CauceSocketConnector =
    Future<CauceSocket> Function(Uri uri, Map<String, String> headers);

/// Quien realmente pone el medio en pantalla (la pantalla de
/// reproducción). El servicio orquesta; nunca renderiza.
abstract class PlaybackApplier {
  /// Muestra una imagen ya descargada. true solo cuando quedó en
  /// pantalla.
  Future<bool> showImage(File file, AssignmentMedia media);

  /// Reproduce un video ya descargado. true solo cuando la
  /// reproducción comenzó.
  Future<bool> showVideo(File file, AssignmentMedia media);

  /// Muestra un PDF ya descargado (render nativo con pdfx). true solo
  /// cuando el documento cargó y quedó en pantalla.
  Future<bool> showPdf(File file, AssignmentMedia media);

  /// Muestra un medio `url` a pantalla completa (WebView in-app donde
  /// la plataforma lo soporta). true solo cuando la página quedó en
  /// pantalla.
  Future<bool> showUrl(Uri url, AssignmentMedia media);

  /// Vuelve al comportamiento por defecto (screensaver).
  Future<bool> showDefault();
}

/// Regla de revisiones del protocolo: `revision` es monótona por
/// dispositivo y una orden solo se aplica si su revision es MAYOR que
/// la última aceptada. Órdenes atrasadas (reconexiones, duplicados)
/// jamás sustituyen el estado más reciente. Puro, sin sockets.
class RevisionGate {
  int? _lastAccepted;

  int? get lastAccepted => _lastAccepted;

  bool shouldApply(int revision) => revision > (_lastAccepted ?? 0);

  /// Acepta la revisión en el momento de ENCOLAR la orden (no al
  /// terminar de aplicarla): los duplicados que lleguen durante la
  /// descarga se descartan igualmente.
  void mark(int revision) {
    if (revision > (_lastAccepted ?? 0)) _lastAccepted = revision;
  }

  /// El servidor confirmó que no hay asignación vigente: la próxima
  /// primera asignación vuelve a empezar en revision 1.
  void reset() => _lastAccepted = null;
}

/// Conexión WebSocket persistente servidor → dispositivo para recibir
/// la asignación vigente (`playback.sync`) y sus cambios
/// (`playback.command`). NO sustituye al heartbeat: la conectividad y
/// `current_media` siguen determinándose exclusivamente por heartbeats.
///
/// Robustez:
/// - Reconexión automática con backoff incremental y tope, sin ciclos
///   concurrentes (un solo intento en vuelo, generación que invalida
///   eventos de conexiones viejas).
/// - Parseo estricto: mensajes malformados se ignoran y loguean, jamás
///   rompen la conexión ni la UI.
/// - El WS caído no afecta al reproductor: el contenido actual sigue.
/// - `playbackState.setPlaying` SOLO cuando el applier confirma que el
///   medio está en pantalla; un ACK jamás sincroniza nada.
class PlaybackSocketService {
  PlaybackSocketService({
    required this.baseUrl,
    required this.deviceUid,
    required this.playbackState,
    this.deviceKey,
    this.cacheDir,
    CauceMediaDownloader? downloader,
    CauceSocketConnector? connector,
    PowerExecutor? powerExecutor,
    Future<void> Function(Duration delay)? wait,
    this.backoffSchedule = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  })  : _downloader = downloader ?? CauceMediaDownloader(deviceKey: deviceKey),
        _connector = connector ?? connectDefault,
        _powerExecutor = powerExecutor ?? const MethodChannelPowerExecutor(),
        _wait = wait ?? defaultWait;

  /// URL base del servidor HTTP (p. ej. http://10.15.1.150:8000). El
  /// esquema se convierte a ws:// (o wss:// para https).
  final String baseUrl;

  /// Identidad estable del dispositivo, la misma que usa el heartbeat.
  final String deviceUid;

  /// Secreto compartido con el servidor (header X-Device-Key). null
  /// cuando el servidor no lo exige (modo transición). JAMÁS se
  /// loguea.
  final String? deviceKey;

  /// Estado compartido con el heartbeat: el medio confirmado en
  /// pantalla.
  final PlaybackState playbackState;

  /// Directorio de caché de medios (path_provider en producción).
  final Future<Directory> Function()? cacheDir;

  final CauceMediaDownloader _downloader;
  final CauceSocketConnector _connector;
  final PowerExecutor _powerExecutor;
  final Future<void> Function(Duration delay) _wait;
  final List<Duration> backoffSchedule;

  final Random _random = Random();

  CauceSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  PlaybackApplier? _applier;
  final RevisionGate _gate = RevisionGate();

  /// Última orden encolada para el applier. La newest gana (coalescing):
  /// órdenes intermedias que lleguen durante una aplicación en curso no
  /// se ejecutan, no se encolan en serie.
  _PendingTarget? _pending;
  bool _applying = false;

  bool _started = false;
  bool _disposed = false;
  bool _connecting = false;
  int _generation = 0;
  int _backoffIndex = 0;

  /// Contador de intentos de conexión (pruebas y diagnóstico).
  int connectAttempts = 0;

  bool get isConnected => _socket != null;

  int? get lastAcceptedRevision => _gate.lastAccepted;

  /// URI del WS del contrato: `ws://host/api/devices/<uid-encoded>/ws`.
  static Uri wsUri(String baseUrl, String deviceUid) {
    final base = Uri.parse(baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final port = base.hasPort ? ':${base.port}' : '';
    return Uri.parse(
      '$scheme://${base.host}$port'
      '/api/devices/${Uri.encodeComponent(deviceUid)}/ws',
    );
  }

  /// Conector de producción: IOWebSocketChannel con el header del
  /// dispositivo. `ready` lanza si el handshake es rechazado (p. ej.
  /// close 1008 "Invalid device key"), lo que se traduce en
  /// reconexión silenciosa.
  static Future<CauceSocket> connectDefault(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final channel = IOWebSocketChannel.connect(uri, headers: headers);
    await channel.ready;
    return _IOWebSocketAdapter(channel);
  }

  /// Espera por defecto entre reconexiones (reemplazable en pruebas).
  static Future<void> defaultWait(Duration delay) =>
      Future<void>.delayed(delay);

  /// Arranca el ciclo de conexión. Idempotente.
  void start() {
    if (_disposed || _started) return;
    _started = true;
    debugPrint(
      '[CAUCE] Servicio playback WS iniciado '
      '(uri=${wsUri(baseUrl, deviceUid)}, device_uid="$deviceUid")',
    );
    unawaited(_connect());
  }

  /// Registra al applier (la pantalla). Si hay órdenes pendientes de
  /// antes del registro, se aplican ahora.
  void attach(PlaybackApplier applier) {
    if (_disposed) return;
    _applier = applier;
    unawaited(_drain());
  }

  void detach(PlaybackApplier applier) {
    if (_applier == applier) _applier = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    unawaited(_socket?.close());
    _socket = null;
    _downloader.dispose();
  }

  // --- Ciclo de conexión ---

  Future<void> _connect() async {
    if (_disposed || _connecting || _socket != null) return;
    _connecting = true;
    final generation = _generation;
    connectAttempts++;
    try {
      final headers = <String, String>{
        if (deviceKey != null) 'X-Device-Key': deviceKey!,
      };
      final socket = await _connector(wsUri(baseUrl, deviceUid), headers);
      if (_disposed || generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      _backoffIndex = 0;
      debugPrint('[CAUCE] WS playback conectado');
      _subscription = socket.stream.listen(
        (data) {
          if (generation == _generation) _onData(data);
        },
        onError: (Object error) {
          if (generation == _generation) {
            debugPrint('[CAUCE] WS playback error de conexión: $error');
            _onDisconnected();
          }
        },
        onDone: () {
          if (generation == _generation) _onDisconnected();
        },
      );
    } catch (e) {
      debugPrint('[CAUCE] WS playback no pudo conectar: $e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onDisconnected() {
    if (_disposed || _socket == null) return;
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_backoffIndex < backoffSchedule.length - 1) {
      _backoffIndex++;
    }
    final delay = backoffSchedule[_backoffIndex] + _jitter();
    // Log solo del primer fallo de una racha: sin spam mientras el
    // servidor está caído.
    if (_backoffIndex == 1) {
      debugPrint(
        '[CAUCE] WS playback desconectado; reconexión con backoff '
        '(tope ${backoffSchedule.last.inSeconds}s)',
      );
    }
    unawaited(
      _wait(delay).then((_) {
        if (!_disposed && _socket == null) _connect();
      }),
    );
  }

  Duration _jitter() =>
      Duration(milliseconds: _random.nextInt(1000) - 500);

  // --- Mensajes del servidor ---

  void _onData(Object? data) {
    if (data is! String) {
      debugPrint('[CAUCE] WS playback: frame no textual ignorado');
      return;
    }

    // Despacho explícito por tipo: `power.command` es un flujo
    // independiente de playback (no pasa por RevisionGate ni por el
    // applier). Un power malformado cae al parseo de playback, que
    // también lo rechaza: se ignora y loguea, jamás se rompe el socket
    // y jamás se responde sin un command_id fiable.
    final powerCommand = PowerCommand.fromJsonString(data);
    if (powerCommand != null) {
      unawaited(_handlePowerCommand(powerCommand));
      return;
    }

    final message = PlaybackServerMessage.fromJsonString(data);
    if (message == null) {
      debugPrint('[CAUCE] WS playback: mensaje malformado ignorado');
      return;
    }
    final assignment = message.assignment;
    if (assignment == null) {
      _onNoAssignment();
    } else {
      _onOrder(assignment);
    }
  }

  /// Ejecuta un `power.command` vía el ejecutor y responde SIEMPRE por
  /// el socket actual: `power.ack` si se aplicó, `power.error` con un
  /// código estable si no. Si el socket ya murió, `_sendRaw` lo deja
  /// en best-effort y el patrón de reconexión ya existe.
  ///
  /// El comando NUNCA interrumpe la reproducción ni al applier, y el
  /// ACK solo confirma recibo/ejecución: el estado real de la pantalla
  /// lo sigue reportando el heartbeat (`device_state`).
  Future<void> _handlePowerCommand(PowerCommand command) async {
    final on = command.action == PowerAction.on;
    debugPrint(
      '[CAUCE] WS playback: power ${on ? 'on' : 'off'} '
      '(command_id ${command.commandId})',
    );
    try {
      final ok = on
          ? await _powerExecutor.wakeScreen()
          : await _powerExecutor.enterStandby();
      if (ok) {
        debugPrint(
          '[CAUCE] Power ${on ? 'on' : 'off'} aplicado; ACK '
          '${command.commandId}',
        );
        _sendRaw(powerAckJson(commandId: command.commandId));
        return;
      }
      // Fallo sin excepción: la plataforma declara la acción no
      // permitida. Android para "off" (standby_denied); cualquier otra
      // plataforma queda cubierta por el mismo código estable.
      debugPrint(
        '[CAUCE] Power ${on ? 'on' : 'off'} no permitido por la plataforma',
      );
      _sendRaw(powerErrorJson(
        commandId: command.commandId,
        code: PowerErrorCodes.standbyDenied,
        message: on
            ? 'la plataforma no permitió encender la pantalla'
            : 'la plataforma no permite entrar en espera',
      ));
    } on PowerExecutorException catch (e) {
      debugPrint('[CAUCE] Power falló (${e.code}): ${e.message}');
      _sendRaw(powerErrorJson(
        commandId: command.commandId,
        code: e.code,
        message: e.message,
      ));
    } catch (e) {
      debugPrint('[CAUCE] Error inesperado ejecutando power: $e');
      _sendRaw(powerErrorJson(
        commandId: command.commandId,
        code: PowerErrorCodes.internalError,
        message: 'error inesperado ejecutando power: $e',
      ));
    }
  }

  /// `assignment: null` es el estado inequívoco "sin asignación":
  /// volver al comportamiento por defecto y dejar de reportar
  /// `current_media`.
  void _onNoAssignment() {
    debugPrint('[CAUCE] WS playback: sin asignación (modo por defecto)');
    _gate.reset();
    _pending = _PendingTarget(null);
    unawaited(_drain());
  }

  void _onOrder(AssignmentMessage assignment) {
    if (!_gate.shouldApply(assignment.revision)) {
      debugPrint(
        '[CAUCE] WS playback: orden revision ${assignment.revision} '
        'ignorada (última aceptada: ${_gate.lastAccepted ?? 0})',
      );
      return;
    }
    _gate.mark(assignment.revision);
    _pending = _PendingTarget(assignment);
    unawaited(_drain());
  }

  // --- Aplicación de la asignación ---

  Future<void> _drain() async {
    if (_applying || _disposed) return;
    while (_pending != null && _applier != null && !_disposed) {
      final target = _pending!;
      _pending = null;
      _applying = true;
      try {
        await _applyTarget(target);
      } finally {
        _applying = false;
      }
    }
  }

  Future<void> _applyTarget(_PendingTarget target) async {
    final applier = _applier;
    if (applier == null) return;

    final assignment = target.assignment;
    if (assignment == null) {
      try {
        final ok = await applier.showDefault();
        if (ok) {
          playbackState.clear();
        } else {
          debugPrint('[CAUCE] No se pudo volver al modo por defecto');
        }
      } catch (e) {
        debugPrint('[CAUCE] Error volviendo al modo por defecto: $e');
      }
      return;
    }

    switch (assignment.media.mediaType) {
      case PlaybackMediaType.url:
        await _applyUrl(applier, assignment);
      case PlaybackMediaType.image:
      case PlaybackMediaType.video:
      case PlaybackMediaType.pdf:
        await _applyFile(applier, assignment);
    }
  }

  Future<void> _applyUrl(
    PlaybackApplier applier,
    AssignmentMessage assignment,
  ) async {
    final externalUrl = assignment.media.externalUrl;
    if (externalUrl == null) {
      _sendError(
        assignment,
        PlaybackErrorCodes.displayFailed,
        'external_url ausente para medio tipo url',
      );
      return;
    }
    final Uri url;
    try {
      url = Uri.parse(externalUrl);
    } catch (e) {
      _sendError(
        assignment,
        PlaybackErrorCodes.displayFailed,
        'external_url inválida: $e',
      );
      return;
    }
    await _display(
      applier,
      assignment,
      () => applier.showUrl(url, assignment.media),
    );
  }

  Future<void> _applyFile(
    PlaybackApplier applier,
    AssignmentMessage assignment,
  ) async {
    final File file;
    try {
      final dir = await _resolveCacheDir();
      final destination = CauceMediaDownloader.cacheFileFor(
        dir,
        assignment.media,
      );
      file = await _downloader.ensureDownloaded(
        baseUrl: baseUrl,
        media: assignment.media,
        destination: destination,
      );
    } on MediaDownloadException catch (e) {
      // La descarga falló: error por WS y el heartbeat conserva el
      // último medio CONFIRMADO (o ninguno). Nunca se reporta el
      // nuevo.
      debugPrint('[CAUCE] Descarga fallida: ${e.message}');
      _sendError(assignment, PlaybackErrorCodes.downloadFailed, e.message);
      return;
    } catch (e) {
      debugPrint('[CAUCE] Error preparando caché: $e');
      _sendError(
        assignment,
        PlaybackErrorCodes.downloadFailed,
        'error preparando caché: $e',
      );
      return;
    }

    if (assignment.media.mediaType == PlaybackMediaType.video) {
      await _display(
        applier,
        assignment,
        () => applier.showVideo(file, assignment.media),
      );
    } else if (assignment.media.mediaType == PlaybackMediaType.pdf) {
      await _display(
        applier,
        assignment,
        () => applier.showPdf(file, assignment.media),
      );
    } else {
      await _display(
        applier,
        assignment,
        () => applier.showImage(file, assignment.media),
      );
    }
  }

  /// Muestra el medio y, SOLO si el applier confirma que quedó en
  /// pantalla, reporta `current_media` al estado compartido y envía el
  /// ACK. Si no, envía `playback.error` y conserva el último medio
  /// confirmado.
  Future<void> _display(
    PlaybackApplier applier,
    AssignmentMessage assignment,
    Future<bool> Function() show,
  ) async {
    bool displayed = false;
    try {
      displayed = await show();
    } catch (e) {
      debugPrint(
        '[CAUCE] Error mostrando medio ${assignment.mediaId}: $e',
      );
      displayed = false;
    }
    if (!displayed) {
      _sendError(
        assignment,
        PlaybackErrorCodes.displayFailed,
        'no se pudo mostrar el medio ${assignment.mediaId}',
      );
      return;
    }
    playbackState.setPlaying(assignment.mediaId);
    _sendAck(assignment);
  }

  Future<Directory> _resolveCacheDir() async {
    if (cacheDir != null) return cacheDir!();
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/cauce_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // --- Mensajes del cliente ---

  /// ACK opcional tras aplicar la orden: el backend solo lo loguea,
  /// no cambia estado. Una vez por orden aceptada.
  void _sendAck(AssignmentMessage assignment) {
    debugPrint(
      '[CAUCE] Medio ${assignment.mediaId} en pantalla; ACK revision '
      '${assignment.revision}',
    );
    _sendRaw(playbackAckJson(
      assignmentId: assignment.assignmentId,
      revision: assignment.revision,
    ));
  }

  void _sendError(
    AssignmentMessage assignment,
    String code,
    String message,
  ) {
    _sendRaw(playbackErrorJson(
      assignmentId: assignment.assignmentId,
      revision: assignment.revision,
      code: code,
      message: message,
    ));
  }

  void _sendRaw(String data) {
    final socket = _socket;
    if (socket == null) return; // best-effort: sin conexión no se envía
    try {
      socket.add(data);
    } catch (e) {
      debugPrint('[CAUCE] WS playback: no se pudo enviar: $e');
    }
  }
}

/// Orden pendiente de aplicar. `assignment == null` significa "volver
/// al modo por defecto" (sync sin asignación).
class _PendingTarget {
  const _PendingTarget(this.assignment);

  final AssignmentMessage? assignment;
}

class _IOWebSocketAdapter implements CauceSocket {
  _IOWebSocketAdapter(this._channel);

  final IOWebSocketChannel _channel;

  @override
  Stream get stream => _channel.stream;

  @override
  void add(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}
