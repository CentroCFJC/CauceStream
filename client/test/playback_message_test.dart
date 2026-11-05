import 'dart:convert';

import 'package:cauce_stream/models/playback_message.dart';
import 'package:cauce_stream/services/playback_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construye un assignment válido del contrato con overrides.
Map<String, dynamic> assignmentJson({
  int assignmentId = 3,
  int mediaId = 5,
  int revision = 2,
  String syncStatus = 'pending',
  Map<String, dynamic>? media,
}) {
  return {
    'assignment_id': assignmentId,
    'media_id': mediaId,
    'revision': revision,
    'sync_status': syncStatus,
    'media': media ??
        {
          'name': 'portada.png',
          'media_type': 'image',
          'mime_type': 'image/png',
          'file_size': 20480,
          'file_url': '/api/media/5/file',
          'external_url': null,
        },
  };
}

Map<String, dynamic> messageJson({
  required String type,
  dynamic assignment,
}) {
  return {
    'type': type,
    'protocol': 1,
    'device_uid': 'SALA 1',
    'assignment': assignment,
    'sent_at': '2026-10-19T18:00:00Z',
  };
}

void main() {
  group('PlaybackServerMessage (parseo estricto del contrato)', () {
    test('playback.sync sin asignación (assignment null)', () {
      final msg = PlaybackServerMessage.fromJsonString(
        jsonEncode(messageJson(type: 'playback.sync', assignment: null)),
      );
      expect(msg, isNotNull);
      expect(msg!.isSync, isTrue);
      expect(msg.deviceUid, 'SALA 1');
      expect(msg.assignment, isNull);
      expect(msg.sentAt, '2026-10-19T18:00:00Z');
    });

    test('playback.command con asignación de imagen', () {
      final msg = PlaybackServerMessage.fromJsonString(
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(),
        )),
      );
      expect(msg, isNotNull);
      expect(msg!.isSync, isFalse);
      final a = msg.assignment!;
      expect(a.assignmentId, 3);
      expect(a.mediaId, 5);
      expect(a.revision, 2);
      expect(a.syncStatus, 'pending');
      expect(a.media.name, 'portada.png');
      expect(a.media.mediaType, PlaybackMediaType.image);
      expect(a.media.mimeType, 'image/png');
      expect(a.media.fileSize, 20480);
      expect(a.media.fileUrl, '/api/media/5/file');
      expect(a.media.externalUrl, isNull);
    });

    test('video con file_url y url con external_url', () {
      final video = PlaybackServerMessage.fromJsonString(
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(media: {
            'name': 'loop.mp4',
            'media_type': 'video',
            'mime_type': 'video/mp4',
            'file_size': null,
            'file_url': '/api/media/6/file',
            'external_url': null,
          }),
        )),
      );
      expect(video!.assignment!.media.mediaType, PlaybackMediaType.video);

      final url = PlaybackServerMessage.fromJsonString(
        jsonEncode(messageJson(
          type: 'playback.sync',
          assignment: assignmentJson(media: {
            'name': 'sitio externo',
            'media_type': 'url',
            'mime_type': null,
            'file_size': null,
            'file_url': null,
            'external_url': 'https://example.com/pantalla',
          }),
        )),
      );
      expect(url!.assignment!.media.mediaType, PlaybackMediaType.url);
      expect(url.assignment!.media.externalUrl, 'https://example.com/pantalla');
    });

    test('pdf con file_url se acepta (se descarga como image/video)', () {
      final pdf = PlaybackServerMessage.fromJsonString(
        jsonEncode(messageJson(
          type: 'playback.sync',
          assignment: assignmentJson(media: {
            'name': 'ficha.pdf',
            'media_type': 'pdf',
            'mime_type': 'application/pdf',
            'file_size': 12345,
            'file_url': '/api/media/9/file',
            'external_url': null,
          }),
        )),
      );
      expect(pdf!.assignment!.media.mediaType, PlaybackMediaType.pdf);
      expect(pdf.assignment!.media.fileUrl, '/api/media/9/file');
    });

    test('rechaza todo lo que se desvía del contrato', () {
      final invalid = <String>[
        // No es JSON.
        'no soy json',
        // No es un objeto.
        '[1, 2]',
        // Tipo desconocido.
        jsonEncode(messageJson(type: 'playback.other', assignment: null)),
        // Protocolo distinto.
        jsonEncode({
          'type': 'playback.sync',
          'protocol': 2,
          'device_uid': 'SALA 1',
          'assignment': null,
          'sent_at': 'x',
        }),
        // Revision inválida (el contrato exige revision >= 1).
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(revision: 0),
        )),
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(revision: -1),
        )),
        // media_id / assignment_id inválidos.
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(mediaId: 0),
        )),
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(assignmentId: 0),
        )),
        // sync_status fuera del dominio.
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(syncStatus: 'synced'),
        )),
        // media ausente.
        jsonEncode({
          'type': 'playback.command',
          'protocol': 1,
          'device_uid': 'SALA 1',
          'assignment': {
            'assignment_id': 3,
            'media_id': 5,
            'revision': 2,
            'sync_status': 'pending',
          },
          'sent_at': 'x',
        }),
        // image sin file_url: no hay nada que descargar.
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(media: {
            'name': 'x.png',
            'media_type': 'image',
            'mime_type': 'image/png',
            'file_size': null,
            'file_url': null,
            'external_url': null,
          }),
        )),
        // url sin external_url.
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(media: {
            'name': 'x',
            'media_type': 'url',
            'mime_type': null,
            'file_size': null,
            'file_url': null,
            'external_url': null,
          }),
        )),
        // media_type desconocido.
        jsonEncode(messageJson(
          type: 'playback.command',
          assignment: assignmentJson(media: {
            'name': 'x',
            'media_type': 'docx',
            'mime_type': null,
            'file_size': null,
            'file_url': '/api/media/5/file',
            'external_url': null,
          }),
        )),
        // device_uid ausente.
        jsonEncode({
          'type': 'playback.sync',
          'protocol': 1,
          'assignment': null,
          'sent_at': 'x',
        }),
      ];

      for (final raw in invalid) {
        expect(
          PlaybackServerMessage.fromJsonString(raw),
          isNull,
          reason: 'debía rechazarse: $raw',
        );
      }
    });
  });

  group('Encoders cliente → servidor', () {
    test('playback.ack con assignment_id y revision', () {
      final decoded =
          jsonDecode(playbackAckJson(assignmentId: 3, revision: 2))
              as Map<String, dynamic>;
      expect(decoded, {
        'type': 'playback.ack',
        'assignment_id': 3,
        'revision': 2,
      });
    });

    test('playback.error trunca code (<=50) y message (<=500)', () {
      final decoded = jsonDecode(playbackErrorJson(
        assignmentId: 3,
        revision: 2,
        code: 'c' * 80,
        message: 'm' * 600,
      )) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>;
      expect(decoded['type'], 'playback.error');
      expect((error['code'] as String).length, 50);
      expect((error['message'] as String).length, 500);
    });
  });

  group('PowerCommand (parseo estricto del contrato)', () {
    Map<String, dynamic> powerJson({
      String type = 'power.command',
      int protocol = 1,
      int commandId = 3,
      String action = 'on',
      String deviceUid = 'SALA 1',
      dynamic sentAt = '2026-10-19T18:00:00Z',
    }) =>
        {
          'type': type,
          'protocol': protocol,
          'device_uid': deviceUid,
          'command_id': commandId,
          'action': action,
          'sent_at': sentAt,
        };

    test('power.command on válido', () {
      final cmd = PowerCommand.fromJsonString(
        jsonEncode(powerJson(commandId: 7, action: 'on')),
      );
      expect(cmd, isNotNull);
      expect(cmd!.commandId, 7);
      expect(cmd.action, PowerAction.on);
      expect(cmd.deviceUid, 'SALA 1');
      expect(cmd.sentAt, '2026-10-19T18:00:00Z');
    });

    test('power.command off válido; sent_at opcional', () {
      final cmd = PowerCommand.fromJsonString(
        jsonEncode(powerJson(action: 'off', sentAt: null)),
      );
      expect(cmd, isNotNull);
      expect(cmd!.action, PowerAction.off);
      expect(cmd.sentAt, isNull);
    });

    test('rechaza protocolo distinto de 1', () {
      expect(
        PowerCommand.fromJsonString(
          jsonEncode(powerJson(protocol: 2)),
        ),
        isNull,
      );
    });

    test('rechaza command_id inválido (0, negativo, flotante, texto, ausente)',
        () {
      String raw(Object? commandId) => jsonEncode({
            'type': 'power.command',
            'protocol': 1,
            'device_uid': 'SALA 1',
            'command_id': commandId,
            'action': 'on',
            'sent_at': null,
          });
      for (final invalid in [0, -1, 2.5, '3', null]) {
        expect(
          PowerCommand.fromJsonString(raw(invalid)),
          isNull,
          reason: 'command_id=$invalid',
        );
      }
    });

    test('rechaza acción fuera de on/off', () {
      expect(
        PowerCommand.fromJsonString(
          jsonEncode(powerJson(action: 'toggle')),
        ),
        isNull,
      );
    });

    test('rechaza device_uid vacío o ausente', () {
      expect(
        PowerCommand.fromJsonString(jsonEncode(powerJson(deviceUid: ''))),
        isNull,
      );
      String raw() => jsonEncode({
            'type': 'power.command',
            'protocol': 1,
            'command_id': 3,
            'action': 'on',
            'sent_at': null,
          });
      expect(PowerCommand.fromJsonString(raw()), isNull);
    });

    test('solo acepta type power.command (playback y desconocidos → null)',
        () {
      expect(
        PowerCommand.fromJsonString(
          jsonEncode(messageJson(type: 'playback.sync', assignment: null)),
        ),
        isNull,
      );
      expect(
        PowerCommand.fromJsonString(
          jsonEncode(powerJson(type: 'power.sync')),
        ),
        isNull,
      );
    });

    test('JSON roto → null, jamás lanza', () {
      expect(PowerCommand.fromJsonString('{no es json'), isNull);
      expect(PowerCommand.fromJsonString('[]'), isNull);
    });
  });

  group('power encoders (límites del contrato)', () {
    test('powerAckJson codifica el command_id', () {
      final decoded =
          jsonDecode(powerAckJson(commandId: 3)) as Map<String, dynamic>;
      expect(decoded['type'], 'power.ack');
      expect(decoded['command_id'], 3);
    });

    test('powerErrorJson codifica error con code y message', () {
      final decoded = jsonDecode(powerErrorJson(
        commandId: 3,
        code: PowerErrorCodes.standbyDenied,
        message: 'la plataforma no permite entrar en espera',
      )) as Map<String, dynamic>;
      expect(decoded['type'], 'power.error');
      expect(decoded['command_id'], 3);
      final error = decoded['error'] as Map<String, dynamic>;
      expect(error['code'], 'standby_denied');
      expect(error['message'], 'la plataforma no permite entrar en espera');
    });

    test('powerErrorJson trunca code (<=50) y message (<=500)', () {
      final decoded = jsonDecode(powerErrorJson(
        commandId: 3,
        code: 'c' * 80,
        message: 'm' * 600,
      )) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>;
      expect((error['code'] as String).length, 50);
      expect((error['message'] as String).length, 500);
    });
  });

  group('RevisionGate (regla de revisiones, puro)', () {
    test('solo aplica revisiones mayores que la última aceptada', () {
      final gate = RevisionGate();
      expect(gate.lastAccepted, isNull);
      expect(gate.shouldApply(1), isTrue, reason: 'primera orden');
      gate.mark(1);
      expect(gate.shouldApply(1), isFalse, reason: 'duplicado');
      expect(gate.shouldApply(0), isFalse, reason: 'atrasada');
      expect(gate.shouldApply(2), isTrue);
      gate.mark(2);
      expect(gate.shouldApply(2), isFalse);
      expect(gate.shouldApply(3), isTrue);
    });

    test('reset permite la revision 1 tras quedar sin asignación', () {
      final gate = RevisionGate();
      gate.mark(7);
      gate.reset();
      expect(gate.lastAccepted, isNull);
      expect(gate.shouldApply(1), isTrue);
    });
  });

  group('PlaybackSocketService.wsUri', () {
    test('convierte http a ws y URL-encodea el uid', () {
      final uri = PlaybackSocketService.wsUri(
        'http://10.15.1.150:8000',
        'SALA PANTALLA 1',
      );
      expect(uri.scheme, 'ws');
      expect(uri.host, '10.15.1.150');
      expect(uri.port, 8000);
      expect(
        uri.path,
        '/api/devices/SALA%20PANTALLA%201/ws',
      );
    });

    test('https se convierte a wss', () {
      final uri =
          PlaybackSocketService.wsUri('https://cauce.example', 'TV1');
      expect(uri.scheme, 'wss');
      expect(uri.path, '/api/devices/TV1/ws');
    });
  });
}
