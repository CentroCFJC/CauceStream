/// Modelos de dominio del frontend.
///
/// `Assignment` refleja el esquema `AssignmentRead` del backend
/// (app/schemas/assignment.py): la asignacion vigente de un
/// dispositivo (un medio por dispositivo) y su estado de
/// sincronizacion. El `sync_status` es dinamico y lo mueve el
/// servidor cuando el heartbeat del dispositivo reporta reproducir
/// el medio asignado: la UI nunca lo computa ni lo asume, solo lo
/// muestra tal como llega.
library;

class Assignment {
  const Assignment({
    required this.id,
    required this.deviceId,
    required this.deviceUid,
    required this.mediaId,
    required this.mediaName,
    required this.syncStatus,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.delivered,
  });

  final int id;
  final int deviceId;

  /// Identificador estable del dispositivo asignatario.
  final String deviceUid;

  /// Identificador del medio en la biblioteca (nunca el nombre: la
  /// identidad es el id, el nombre es solo display).
  final int mediaId;
  final String mediaName;

  /// 'synchronized' | 'pending'. Dinamico: lo actualiza el backend;
  /// el polling del inventario lo refleja en la UI.
  final String syncStatus;

  /// Version de la asignacion: incrementa en cada reemplazo.
  final int revision;

  /// Solo en la respuesta del PUT de asignacion (null en los GET):
  /// estrictamente "el comando se escribio al socket vivo del
  /// dispositivo sin error". No es confirmacion de recepcion ni de
  /// ejecucion; eso sigue siendo exclusivo del heartbeat
  /// (sync_status). null = el servidor no informo (GET de lista).
  final bool? delivered;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Assignment.fromJson(Map<String, dynamic> json) => Assignment(
    id: json['id'] as int,
    deviceId: json['device_id'] as int,
    deviceUid: json['device_uid'] as String,
    mediaId: json['media_id'] as int,
    mediaName: json['media_name'] as String,
    syncStatus: json['sync_status'] as String? ?? 'pending',
    revision: json['revision'] as int,
    delivered: json['delivered'] as bool?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  bool get isSynchronized => syncStatus == 'synchronized';

  String get syncLabel => isSynchronized ? 'Sincronizado' : 'Pendiente';
}
