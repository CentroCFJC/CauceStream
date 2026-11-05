/// Modelos tipados del protocolo de reproducción por WebSocket (v1).
///
/// Contrato (backend, `playback.sync` / `playback.command`): parseo
/// estricto — cualquier desviación deforma el mensaje en `null`, que el
/// servicio ignora y loguea. Nunca lanza.
///
/// El cliente solo ENVIAR `playback.ack` y `playback.error`; los
/// encoders correspondientes viven aquí.
library;

import 'dart:convert';

/// Tipos de medio que el backend puede asignar (contrato `media_type`).
enum PlaybackMediaType { image, video, url, pdf }

/// Códigos de error admitidos por el contrato del backend en
/// `playback.error` (code ≤ 50, message ≤ 500).
class PlaybackErrorCodes {
  PlaybackErrorCodes._();

  static const String downloadFailed = 'download_failed';
  static const String displayFailed = 'display_failed';
}

/// Acciones del comando de energía (`power.command`).
///
/// `on` = salir de espera (encender pantalla); `off` = entrar en espera
/// (apagar pantalla; el dispositivo NO se apaga).
enum PowerAction { on, off }

/// Códigos de error estables para `power.error` (code ≤ 50, message ≤ 500).
class PowerErrorCodes {
  PowerErrorCodes._();

  /// La plataforma no permite entrar en espera desde una app sin
  /// privilegios de administración (Android sin la app aprovisionada como
  /// Device Owner / Device Admin: no existe API pública para apagar la
  /// pantalla).
  static const String standbyDenied = 'standby_denied';

  /// La plataforma no tiene implementación del canal de energía.
  static const String platformUnsupported = 'platform_unsupported';

  /// Fallo inesperado ejecutando el comando.
  static const String internalError = 'internal_error';
}

/// El medio asignado (objeto `assignment.media` del contrato).
class AssignmentMedia {
  const AssignmentMedia({
    required this.name,
    required this.mediaType,
    required this.fileUrl,
    required this.externalUrl,
    this.mimeType,
    this.fileSize,
  });

  final String name;
  final PlaybackMediaType mediaType;
  final String? mimeType;
  final int? fileSize;

  /// Endpoint de descarga RELATIVO (`/api/media/{id}/file`), solo para
  /// `image`/`video`. null para `url`.
  final String? fileUrl;

  /// URL externa tal cual la registra el backend, solo para `url`.
  final String? externalUrl;

  static AssignmentMedia? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;

    final mediaTypeText = json['media_type'];
    final PlaybackMediaType mediaType;
    switch (mediaTypeText) {
      case 'image':
        mediaType = PlaybackMediaType.image;
      case 'video':
        mediaType = PlaybackMediaType.video;
      case 'url':
        mediaType = PlaybackMediaType.url;
      case 'pdf':
        mediaType = PlaybackMediaType.pdf;
      default:
        return null;
    }

    final mimeType = json['mime_type'];
    if (mimeType != null && mimeType is! String) return null;

    final fileSize = _readNonNegativeInt(json['file_size']);

    final fileUrl = json['file_url'];
    if (fileUrl != null && (fileUrl is! String || fileUrl.isEmpty)) {
      return null;
    }
    final externalUrl = json['external_url'];
    if (externalUrl != null && (externalUrl is! String || externalUrl.isEmpty)) {
      return null;
    }

    // Un image/video se descarga del endpoint del backend: file_url es
    // obligatorio. Un url se muestra con external_url tal cual: jamás se
    // convierte en archivo descargable.
    if (mediaType != PlaybackMediaType.url &&
        (fileUrl == null || fileUrl.isEmpty)) {
      return null;
    }
    if (mediaType == PlaybackMediaType.url &&
        (externalUrl == null || externalUrl.isEmpty)) {
      return null;
    }

    return AssignmentMedia(
      name: name,
      mediaType: mediaType,
      mimeType: mimeType as String?,
      fileSize: fileSize,
      fileUrl: fileUrl as String?,
      externalUrl: externalUrl as String?,
    );
  }
}

/// La asignación vigente (`assignment` en sync/command).
class AssignmentMessage {
  const AssignmentMessage({
    required this.assignmentId,
    required this.mediaId,
    required this.revision,
    required this.syncStatus,
    required this.media,
  });

  final int assignmentId;

  /// Identificador estable del medio (Media.id del backend). Es el valor
  /// que el heartbeat reporta en `payload.current_media` cuando el
  /// reproductor confirma la reproducción.
  final int mediaId;

  /// Monótona por dispositivo: solo se aplican revisiones mayores que
  /// la última aceptada.
  final int revision;

  /// Estado persistido en el instante del envío ('synchronized' |
  /// 'pending'). Informativo: el cliente no lo usa para decidir nada.
  final String syncStatus;
  final AssignmentMedia media;

  static AssignmentMessage? fromJson(Map<String, dynamic> json) {
    final assignmentId = _readPositiveInt(json['assignment_id']);
    final mediaId = _readPositiveInt(json['media_id']);
    final revision = _readPositiveInt(json['revision']);
    if (assignmentId == null || mediaId == null || revision == null) {
      return null;
    }

    final syncStatus = json['sync_status'];
    if (syncStatus is! String ||
        (syncStatus != 'pending' && syncStatus != 'synchronized')) {
      return null;
    }

    final mediaJson = json['media'];
    if (mediaJson is! Map<String, dynamic>) return null;
    final media = AssignmentMedia.fromJson(mediaJson);
    if (media == null) return null;

    return AssignmentMessage(
      assignmentId: assignmentId,
      mediaId: mediaId,
      revision: revision,
      syncStatus: syncStatus,
      media: media,
    );
  }
}

/// Mensaje servidor → cliente (`playback.sync` o `playback.command`).
///
/// `assignment == null` es el estado inequívoco "sin asignación": el
/// cliente vuelve a su comportamiento por defecto (screensaver) y deja
/// de reportar `current_media`.
class PlaybackServerMessage {
  const PlaybackServerMessage({
    required this.isSync,
    required this.deviceUid,
    required this.assignment,
    required this.sentAt,
  });

  /// true para `playback.sync`; false para `playback.command`.
  final bool isSync;
  final String deviceUid;
  final AssignmentMessage? assignment;
  final String? sentAt;

  /// Parseo estricto. Devuelve null ante cualquier mensaje malformado o
  /// de protocolo desconocido (se ignora y loguea, nunca se crashea).
  static PlaybackServerMessage? fromJsonString(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final type = decoded['type'];
    final bool isSync;
    switch (type) {
      case 'playback.sync':
        isSync = true;
      case 'playback.command':
        isSync = false;
      default:
        return null;
    }

    final protocol = _readPositiveInt(decoded['protocol']);
    if (protocol != 1) return null;

    final deviceUid = decoded['device_uid'];
    if (deviceUid is! String || deviceUid.isEmpty) return null;

    final sentAt = decoded['sent_at'];
    if (sentAt != null && sentAt is! String) return null;

    final assignmentJson = decoded['assignment'];
    AssignmentMessage? assignment;
    if (assignmentJson != null) {
      if (assignmentJson is! Map<String, dynamic>) return null;
      assignment = AssignmentMessage.fromJson(assignmentJson);
      if (assignment == null) return null;
    }

    return PlaybackServerMessage(
      isSync: isSync,
      deviceUid: deviceUid,
      assignment: assignment,
      sentAt: sentAt as String?,
    );
  }
}

/// Mensaje servidor → cliente `power.command` (protocolo v1).
///
/// Comando transitorio: no existe `power.sync`; nada que reconstruir al
/// reconectar. No pasa por `RevisionGate` ni por el applier de playback.
/// El `command_id` identifica el comando para el `power.ack` /
/// `power.error` de respuesta (el backend valida contra el último
/// enviado).
class PowerCommand {
  const PowerCommand({
    required this.commandId,
    required this.action,
    required this.deviceUid,
    required this.sentAt,
  });

  final int commandId;
  final PowerAction action;
  final String deviceUid;
  final String? sentAt;

  /// Parseo estricto espejo de [PlaybackServerMessage.fromJsonString]:
  /// `type == "power.command"`, `protocol == 1`, `command_id` entero
  /// >= 1, `action` en {"on", "off"}, `device_uid` no vacío. Cualquier
  /// desviación → null (se ignora y loguea; jamás se crashea y jamás
  /// se responde sin un `command_id` fiable).
  static PowerCommand? fromJsonString(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final type = decoded['type'];
    if (type != 'power.command') return null;

    final protocol = _readPositiveInt(decoded['protocol']);
    if (protocol != 1) return null;

    final commandId = _readPositiveInt(decoded['command_id']);
    if (commandId == null) return null;

    final actionText = decoded['action'];
    final PowerAction action;
    switch (actionText) {
      case 'on':
        action = PowerAction.on;
      case 'off':
        action = PowerAction.off;
      default:
        return null;
    }

    final deviceUid = decoded['device_uid'];
    if (deviceUid is! String || deviceUid.isEmpty) return null;

    final sentAt = decoded['sent_at'];
    if (sentAt != null && sentAt is! String) return null;

    return PowerCommand(
      commandId: commandId,
      action: action,
      deviceUid: deviceUid,
      sentAt: sentAt as String?,
    );
  }
}

/// Codifica `{"type": "playback.ack", ...}` (opcional, tras aplicar una
/// orden; el backend no cambia estado con él).
String playbackAckJson({
  required int assignmentId,
  required int revision,
}) {
  return jsonEncode({
    'type': 'playback.ack',
    'assignment_id': assignmentId,
    'revision': revision,
  });
}

/// Codifica `{"type": "playback.error", ...}` con code ≤ 50 y
/// message ≤ 500 (límites del contrato; se trunca sin lanzar).
String playbackErrorJson({
  required int assignmentId,
  required int revision,
  required String code,
  required String message,
}) {
  return jsonEncode({
    'type': 'playback.error',
    'assignment_id': assignmentId,
    'revision': revision,
    'error': {
      'code': code.length <= 50 ? code : code.substring(0, 50),
      'message': message.length <= 500 ? message : message.substring(0, 500),
    },
  });
}

/// Codifica `{"type": "power.ack", ...}`: confirma recibo/ejecución del
/// comando. NUNCA reporta estado: el heartbeat (`device_state`) sigue
/// siendo la única fuente de verdad.
String powerAckJson({required int commandId}) {
  return jsonEncode({
    'type': 'power.ack',
    'command_id': commandId,
  });
}

/// Codifica `{"type": "power.error", ...}` con code ≤ 50 y message ≤ 500
/// (límites del contrato; se trunca sin lanzar), espejo de
/// [playbackErrorJson].
String powerErrorJson({
  required int commandId,
  required String code,
  required String message,
}) {
  return jsonEncode({
    'type': 'power.error',
    'command_id': commandId,
    'error': {
      'code': code.length <= 50 ? code : code.substring(0, 50),
      'message': message.length <= 500 ? message : message.substring(0, 500),
    },
  });
}

int? _readPositiveInt(Object? value) {
  if (value is int && value >= 1) return value;
  if (value is num && value == value.round() && value >= 1) {
    return value.round();
  }
  return null;
}

int? _readNonNegativeInt(Object? value) {
  if (value is int && value >= 0) return value;
  if (value is num && value == value.round() && value >= 0) {
    return value.round();
  }
  return null;
}
