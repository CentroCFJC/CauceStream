import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cauce_stream/models/playback_message.dart';
import 'package:cauce_stream/services/cauce_media_downloader.dart';
import 'package:cauce_stream/services/playback_socket_service.dart';
import 'package:cauce_stream/services/playback_state.dart';
import 'package:cauce_stream/services/power_executor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Canal falso: servidor → cliente por [serverSend]/[serverDone];
/// cliente → servidor queda en [sent].
class FakeSocket implements CauceSocket {
  FakeSocket();

  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<String> sent = <String>[];
  bool closed = false;

  @override
  Stream get stream => _incoming.stream;

  @override
  void add(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }

  void serverSend(Object data) => _incoming.add(data);

  void serverDone() {
    unawaited(_incoming.close());
  }
}

/// Conector falso con comportamientos encolables por intento: un error
/// hace fallar el "handshake"; sin comportamiento, conexión aceptada.
class FakeConnector {
  final List<FakeSocket> sockets = [];
  final List<Uri> uris = [];
  final List<Map<String, String>> headers = [];
  final List<Object> failures = [];
  int calls = 0;

  CauceSocketConnector get connector => (uri, hdrs) async {
        calls++;
        uris.add(uri);
        headers.add(Map<String, String>.of(hdrs));
        if (failures.isNotEmpty) {
          final error = failures.removeAt(0);
          if (failures.isEmpty) {
            // último fallo programado: reintenta limpio la próxima vez
          }
          throw error;
        }
        final socket = FakeSocket();
        sockets.add(socket);
        return socket;
      };
}

/// Descargador falso: registra las descargas que el servicio ORDENA y
/// devuelve un archivo sin tocar disco (las pruebas del servicio no
/// dependen de IO real; el header y la URL los verifica
/// cauce_media_downloader_test.dart).
class RecordingDownloader extends CauceMediaDownloader {
  RecordingDownloader()
      : super(
            client: MockClient(
          (request) async => http.Response('', 500),
        ));

  final List<({String fileUrl, String destination})> requests = [];

  /// El próximo ensureDownloaded falla (p. ej. HTTP 404 en el servidor).
  bool failNext = false;

  @override
  Future<File> ensureDownloaded({
    required String baseUrl,
    required AssignmentMedia media,
    required File destination,
  }) async {
    if (failNext) {
      failNext = false;
      throw const MediaDownloadException(
        'descarga fallida: HTTP 404 en /api/media/x/file',
      );
    }
    requests.add(
      (fileUrl: media.fileUrl ?? '', destination: destination.path),
    );
    return destination;
  }
}

class FakeApplier implements PlaybackApplier {
  FakeApplier({this.resultOf});

  /// Decide el resultado por tipo; null → siempre true.
  final bool Function(String kind, AssignmentMedia media)? resultOf;

  final List<String> calls = [];

  @override
  Future<bool> showImage(File file, AssignmentMedia media) async =>
      _record('image', media, file.path);

  @override
  Future<bool> showVideo(File file, AssignmentMedia media) async =>
      _record('video', media, file.path);

  @override
  Future<bool> showUrl(Uri url, AssignmentMedia media) async =>
      _record('url', media, url.toString());

  @override
  Future<bool> showPdf(File file, AssignmentMedia media) async =>
      _record('pdf', media, file.path);

  @override
  Future<bool> showDefault() async {
    calls.add('default');
    return true;
  }

  bool _record(String kind, AssignmentMedia media, String detail) {
    calls.add('$kind:${media.name}:$detail');
    return resultOf?.call(kind, media) ?? true;
  }
}

/// Ejecutor de pantalla falso (como CauceSocketConnector): el servicio
/// nunca depende de platform channels en pruebas. standby=false por
/// defecto espeja el comportamiento real de Android sin aprovisionar
/// (sin Device Owner/Admin no se puede apagar la pantalla).
class FakePowerExecutor implements PowerExecutor {
  FakePowerExecutor({this.wakeResult = true, this.standbyResult = false});

  bool wakeResult;
  bool standbyResult;
  Object? wakeError;
  Object? standbyError;
  final List<String> calls = [];

  @override
  Future<bool> enterStandby() async {
    calls.add('off');
    final error = standbyError;
    if (error != null) throw error;
    return standbyResult;
  }

  @override
  Future<bool> wakeScreen() async {
    calls.add('on');
    final error = wakeError;
    if (error != null) throw error;
    return wakeResult;
  }

  @override
  Future<PowerCapabilities> capabilities() async => const PowerCapabilities(
        canWake: true,
        canStandby: false,
        deviceOwner: false,
        adminActive: false,
      );

  @override
  Future<bool> requestDeviceAdmin() async => false;
}

Map<String, dynamic> powerCommandJson({
  int commandId = 3,
  String action = 'on',
}) =>
    {
      'type': 'power.command',
      'protocol': 1,
      'device_uid': 'SALA 1',
      'command_id': commandId,
      'action': action,
      'sent_at': '2026-10-19T18:00:00Z',
    };

Map<String, dynamic> syncJson({Map<String, dynamic>? assignment}) => {
      'type': 'playback.sync',
      'protocol': 1,
      'device_uid': 'SALA 1',
      'assignment': assignment,
      'sent_at': '2026-10-19T18:00:00Z',
    };

Map<String, dynamic> commandJson(Map<String, dynamic> assignment) => {
      'type': 'playback.command',
      'protocol': 1,
      'device_uid': 'SALA 1',
      'assignment': assignment,
      'sent_at': '2026-10-19T18:00:00Z',
    };

Map<String, dynamic> assignmentJson({
  int assignmentId = 3,
  int mediaId = 5,
  int revision = 2,
  String mediaType = 'image',
  String? fileUrl = '/api/media/5/file',
  String? externalUrl,
}) {
  return {
    'assignment_id': assignmentId,
    'media_id': mediaId,
    'revision': revision,
    'sync_status': 'pending',
    'media': {
      'name': 'medio-$mediaId',
      'media_type': mediaType,
      'mime_type': mediaType == 'image' ? 'image/png' : 'video/mp4',
      'file_size': null,
      'file_url': fileUrl,
      'external_url': externalUrl,
    },
  };
}

void main() {
  setUp(() {
    // Los logs del servicio son útiles en producción; en pruebas, silencio.
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  late Directory tempDir;
  late FakeConnector connector;
  late RecordingDownloader downloader;
  late FakePowerExecutor powerExecutor;
  late PlaybackState playbackState;
  late PlaybackSocketService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cauce_ws_test');
    connector = FakeConnector();
    downloader = RecordingDownloader();
    powerExecutor = FakePowerExecutor();
    playbackState = PlaybackState();
    service = PlaybackSocketService(
      baseUrl: 'http://10.15.1.150:8000',
      deviceUid: 'SALA 1',
      deviceKey: 'secreto-compartido',
      playbackState: playbackState,
      downloader: downloader,
      connector: connector.connector,
      powerExecutor: powerExecutor,
      cacheDir: () async => tempDir,
      wait: (delay) async {}, // reconexión inmediata en pruebas
    )..start();
    await pumpEventQueue();
  });

  tearDown(() async {
    service.dispose();
    await pumpEventQueue();
    await tempDir.delete(recursive: true);
  });

  FakeSocket socket() => connector.sockets.last;

  test('conecta con la URI y el header del contrato', () {
    expect(connector.calls, 1);
    expect(
      connector.uris.single.toString(),
      'ws://10.15.1.150:8000/api/devices/SALA%201/ws',
    );
    expect(
      connector.headers.single,
      {'X-Device-Key': 'secreto-compartido'},
    );
  });

  test('un comando nuevo dispara descarga autenticada + adopción + ACK',
      () async {
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 5, revision: 2)),
    ));
    await pumpEventQueue();

    // Descarga ordenada sobre el endpoint del contrato (relativo a la
    // base de la API); el header X-Device-Key y la URL completa los
    // verifica cauce_media_downloader_test.dart.
    expect(downloader.requests.single.fileUrl, '/api/media/5/file');
    expect(
      downloader.requests.single.destination,
      contains('cauce_media_medio-5'),
    );
    // El applier recibió el archivo ya descargado.
    expect(applier.calls.single, startsWith('image:'));
    // current_media solo tras confirmar pantalla, y ACK una única vez.
    expect(playbackState.currentMediaId, 5);
    expect(socket().sent, [
      jsonEncode({
        'type': 'playback.ack',
        'assignment_id': 3,
        'revision': 2,
      }),
    ]);
  });

  test('un comando con revision vieja se ignora', () async {
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 6, revision: 3)),
    ));
    await pumpEventQueue();
    expect(applier.calls.length, 1);
    expect(playbackState.currentMediaId, 6);
    final acksAfterFirst = socket().sent.length;

    // Duplicada (misma revision) y atrasada (menor): ignoradas.
    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 6, revision: 3)),
    ));
    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 5, revision: 2)),
    ));
    await pumpEventQueue();

    expect(applier.calls.length, 1, reason: 'el applier no cambia de medio');
    expect(socket().sent.length, acksAfterFirst, reason: 'sin ACKs repetidos');
    expect(playbackState.currentMediaId, 6);
  });

  test('un ACK de recepción jamás sincroniza: sin confirmación de pantalla '
      'no se reporta el medio', () async {
    final applier = FakeApplier(resultOf: (_, __) => false);
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 5, revision: 1)),
    ));
    await pumpEventQueue();

    expect(applier.calls, isNotEmpty);
    expect(playbackState.currentMediaId, isNull,
        reason: 'el medio nunca se confirmó en pantalla');
    expect(socket().sent, [
      jsonEncode({
        'type': 'playback.error',
        'assignment_id': 3,
        'revision': 1,
        'error': {
          'code': 'display_failed',
          'message': 'no se pudo mostrar el medio 5',
        },
      }),
    ], reason: 'sin ACK cuando la pantalla no confirma');
  });

  test('descarga fallida: playback.error y el medio anterior sigue '
      'confirmado', () async {
    final applier = FakeApplier();
    service.attach(applier);

    // Primer medio OK.
    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 7, revision: 1)),
    ));
    await pumpEventQueue();
    expect(playbackState.currentMediaId, 7);

    // Ahora el nuevo medio falla al descargar: se reporta el error y
    // el 7 confirmado sigue siendo el current_media.
    downloader.failNext = true;
    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 9, revision: 2)),
    ));
    await pumpEventQueue();

    final errors = socket().sent
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .where((m) => m['type'] == 'playback.error')
        .toList();
    expect(errors, hasLength(1));
    expect((errors.single['error'] as Map)['code'], 'download_failed');
    expect(playbackState.currentMediaId, 7);
  });

  test('sync sin asignación vuelve al modo por defecto y limpia '
      'current_media', () async {
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 5, revision: 1)),
    ));
    await pumpEventQueue();
    expect(playbackState.currentMediaId, 5);

    socket().serverSend(jsonEncode(syncJson(assignment: null)));
    await pumpEventQueue();

    expect(applier.calls.last, 'default');
    expect(playbackState.currentMediaId, isNull);
    // El null no lleva ACK: no hay assignment que confirmar.
    expect(
      socket().sent
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((m) => m['type'] == 'playback.ack'),
      hasLength(1),
    );
  });

  test('medio url se muestra con external_url tal cual (sin descarga)',
      () async {
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(
        mediaId: 8,
        revision: 1,
        mediaType: 'url',
        fileUrl: null,
        externalUrl: 'https://example.com/pantalla',
      )),
    ));
    await pumpEventQueue();

    expect(downloader.requests, isEmpty, reason: 'una url nunca se descarga');
    expect(applier.calls.single, 'url:medio-8:https://example.com/pantalla');
    expect(playbackState.currentMediaId, 8);
  });

  test('medio pdf se descarga y se muestra con showPdf', () async {
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(
        mediaId: 9,
        revision: 1,
        mediaType: 'pdf',
        fileUrl: '/api/media/9/file',
      )),
    ));
    await pumpEventQueue();

    // El pdf se descarga como image/video y cae en showPdf del applier.
    expect(downloader.requests.single.fileUrl, '/api/media/9/file');
    expect(applier.calls.single, startsWith('pdf:medio-9:'));
    expect(playbackState.currentMediaId, 9);
  });

  test('mensajes malformados se ignoran sin cerrar la conexión',
      () async {
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend('no-json');
    socket().serverSend('[1,2]');
    socket().serverSend(jsonEncode({'type': 'otra.cosa'}));
    socket().serverSend(jsonEncode({
      'type': 'playback.command',
      'protocol': 99,
      'device_uid': 'SALA 1',
      'assignment': assignmentJson(),
    }));
    await pumpEventQueue();

    expect(applier.calls, isEmpty);
    expect(socket().closed, isFalse);

    // La conexión sigue viva: una orden válida posterior se aplica.
    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 5, revision: 1)),
    ));
    await pumpEventQueue();
    expect(playbackState.currentMediaId, 5);
  });

  test('reconexión: tras la caída reconecta y retoma el estado vigente',
      () async {
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 5, revision: 4)),
    ));
    await pumpEventQueue();
    expect(playbackState.currentMediaId, 5);

    // El servidor se cae (close normal) y vuelve: el sync vigente
    // reconstruye el estado (revision 4 persistida en el servidor).
    socket().serverDone();
    await pumpEventQueue();
    expect(connector.calls, 2, reason: 'reconectó tras la desconexión');

    connector.sockets.last.serverSend(jsonEncode(
      syncJson(assignment: assignmentJson(mediaId: 5, revision: 4)),
    ));
    await pumpEventQueue();

    expect(playbackState.currentMediaId, 5);
    // La revision 4 ya aplicada no se re-aplica (sin descarga extra ni
    // segundo ACK); el contenido siguió reproduciéndose todo el tiempo.
    expect(downloader.requests, hasLength(1));
  });

  test('ACK perdido tras aplicar (canal muerto antes de la '
      'confirmación): la resincronización no duplica la reproducción',
      () async {
    // Escenario del watchdog del servidor: el comando llegó y se
    // aplicó, pero el ACK se pierde porque el canal murió. El servidor
    // cierra por timeout y el cliente reconecta; el playback.sync con
    // la MISMA revisión debe ignorarse (RevisionGate): una sola
    // descarga, un solo show, sin reproducción inconsistente.
    final applier = FakeApplier();
    service.attach(applier);

    socket().serverSend(jsonEncode(
      commandJson(assignmentJson(mediaId: 7, revision: 9)),
    ));
    await pumpEventQueue();
    expect(playbackState.currentMediaId, 7);
    expect(applier.calls, hasLength(1));

    // El ACK se escribió al canal moribundo; el servidor nunca lo ve.
    expect(
      socket().sent.where((raw) => raw.contains('playback.ack')),
      isNotEmpty,
    );
    socket().serverDone();

    // Reconexión (backoff inmediato en pruebas) y resincronización con
    // la revisión persistida, que ya fue aceptada.
    await pumpEventQueue();
    expect(connector.calls, 2);
    connector.sockets.last.serverSend(jsonEncode(
      syncJson(assignment: assignmentJson(mediaId: 7, revision: 9)),
    ));
    await pumpEventQueue();

    expect(playbackState.currentMediaId, 7);
    expect(downloader.requests, hasLength(1),
        reason: 'la misma revisión jamás se re-aplica');
    expect(applier.calls, hasLength(1));
  });

  test('handshake rechazado (p. ej. 1008): reintenta en silencio y la '
      'app sigue', () async {
    connector.failures.add(const SocketException('1008 Invalid device key'));
    final retryService = PlaybackSocketService(
      baseUrl: 'http://10.15.1.150:8000',
      deviceUid: 'SALA 1',
      deviceKey: 'mala',
      playbackState: playbackState,
      downloader: downloader,
      connector: connector.connector,
      cacheDir: () async => tempDir,
      wait: (delay) async {},
    )..start();
    await pumpEventQueue();

    expect(retryService.isConnected, isTrue, reason: 'reconectó solo');
    expect(playbackState.currentMediaId, isNull,
        reason: 'sin WS funcional no hay medio asignado');
    addTearDown(retryService.dispose);
  });

  test('órdenes recibidas antes del applier se aplican al registrarse',
      () async {
    // Sin attach: la orden queda pendiente (p. ej. pantalla aún no
    // montada). Nada se reporta prematuramente.
    socket().serverSend(jsonEncode(
      syncJson(assignment: assignmentJson(mediaId: 5, revision: 1)),
    ));
    await pumpEventQueue();
    expect(playbackState.currentMediaId, isNull);
    expect(socket().sent, isEmpty);

    final applier = FakeApplier();
    service.attach(applier);
    await pumpEventQueue();

    expect(applier.calls.single, startsWith('image:'));
    expect(playbackState.currentMediaId, 5);
    expect(socket().sent, isNotEmpty);
  });

  test('sin deviceKey el handshake no lleva el header (transición)',
      () async {
    final keylessConnector = FakeConnector();
    final keylessService = PlaybackSocketService(
      baseUrl: 'http://10.15.1.150:8000',
      deviceUid: 'SALA 1',
      playbackState: playbackState,
      downloader: downloader,
      connector: keylessConnector.connector,
      powerExecutor: powerExecutor,
      cacheDir: () async => tempDir,
      wait: (delay) async {},
    )..start();
    await pumpEventQueue();
    addTearDown(keylessService.dispose);

    expect(keylessConnector.headers.single, isEmpty);
  });

  group('power.command (canal compartido, flujo independiente)', () {
    test('power on durante reproducción: ACK sin tocar playback ni applier',
        () async {
      final applier = FakeApplier();
      service.attach(applier);

      // Reproducción en curso que no debe interrumpirse.
      socket().serverSend(jsonEncode(
        commandJson(assignmentJson(mediaId: 5, revision: 1)),
      ));
      await pumpEventQueue();
      expect(playbackState.currentMediaId, 5);
      final applierCalls = List.of(applier.calls);
      final sentBefore = socket().sent.length;

      socket().serverSend(jsonEncode(
        powerCommandJson(commandId: 9, action: 'on'),
      ));
      await pumpEventQueue();

      expect(powerExecutor.calls, ['on']);
      expect(
        socket().sent.last,
        jsonEncode({'type': 'power.ack', 'command_id': 9}),
      );
      expect(
        applier.calls,
        applierCalls,
        reason: 'el applier nunca ve el comando power',
      );
      expect(
        playbackState.currentMediaId,
        5,
        reason: 'el medio sigue reproduciéndose',
      );
      // El ACK de power es el único mensaje nuevo.
      expect(socket().sent.length, sentBefore + 1);
      expect(socket().closed, isFalse);
    });

    test('power off no soportado (Android): power.error standby_denied',
        () async {
      socket().serverSend(jsonEncode(
        powerCommandJson(commandId: 4, action: 'off'),
      ));
      await pumpEventQueue();

      expect(powerExecutor.calls, ['off']);
      final error = jsonDecode(socket().sent.single) as Map<String, dynamic>;
      expect(error['type'], 'power.error');
      expect(error['command_id'], 4);
      expect((error['error'] as Map)['code'], 'standby_denied');
    });

    test('power off soportado por la plataforma: ACK (ruta futura)',
        () async {
      powerExecutor.standbyResult = true;
      socket().serverSend(jsonEncode(
        powerCommandJson(commandId: 5, action: 'off'),
      ));
      await pumpEventQueue();

      expect(
        socket().sent.single,
        jsonEncode({'type': 'power.ack', 'command_id': 5}),
      );
    });

    test('ejecutor que lanza PowerExecutorException: error con su código',
        () async {
      powerExecutor.wakeError = const PowerExecutorException(
        PowerErrorCodes.platformUnsupported,
        'sin canal nativo',
      );
      socket().serverSend(jsonEncode(
        powerCommandJson(commandId: 6, action: 'on'),
      ));
      await pumpEventQueue();

      final error = jsonDecode(socket().sent.single) as Map<String, dynamic>;
      expect((error['error'] as Map)['code'], 'platform_unsupported');
    });

    test('error inesperado del ejecutor: power.error internal_error',
        () async {
      powerExecutor.wakeError = Exception('boom');
      socket().serverSend(jsonEncode(
        powerCommandJson(commandId: 7, action: 'on'),
      ));
      await pumpEventQueue();

      final error = jsonDecode(socket().sent.single) as Map<String, dynamic>;
      expect(error['command_id'], 7);
      expect((error['error'] as Map)['code'], 'internal_error');
    });

    test('power.command malformado: ignorado sin respuesta y sin romper el '
        'socket', () async {
      final applier = FakeApplier();
      service.attach(applier);

      // Sin command_id no hay respuesta fiable: nada se envía.
      socket().serverSend(jsonEncode({
        'type': 'power.command',
        'protocol': 1,
        'device_uid': 'SALA 1',
        'action': 'on',
        'sent_at': null,
      }));
      await pumpEventQueue();

      expect(powerExecutor.calls, isEmpty);
      expect(socket().sent, isEmpty);
      expect(applier.calls, isEmpty);
      expect(socket().closed, isFalse);

      // El socket sigue operativo para playback.
      socket().serverSend(jsonEncode(
        commandJson(assignmentJson(mediaId: 5, revision: 1)),
      ));
      await pumpEventQueue();
      expect(playbackState.currentMediaId, 5);
    });
  });
}
