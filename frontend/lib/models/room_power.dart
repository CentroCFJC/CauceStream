/// Modelos del endpoint TEMPORAL de encendido/apagado maestro de la
/// sala (POST/GET /api/room/power).
///
/// Reflejan los esquemas `RoomPowerAccepted`, `RoomTaskStatus` y
/// `RoomPowerStatus` del backend (app/schemas/room.py). La semantica
/// es clave: el 202 del POST solo confirma que la tarea programada de
/// Windows fue DISPARADA; el resultado real (exito de la ultima
/// ejecucion de cada tarea) se consulta con el GET. Ver
/// backend/docs/room_power_temporal.md.
library;

/// Accion maestra sobre toda la sala.
enum RoomPowerAction {
  /// Encender: dispara la tarea programada Cauce_ON.
  on,

  /// Apagar: dispara la tarea programada Cauce_OFF.
  off;

  /// Valor que viaja en el cuerpo del POST: {"action": "on"|"off"}.
  String get wireName => name;

  /// Parsea el valor del contrato; lanza FormatException con
  /// cualquier otra cosa (respuestas corruptas no pasan silenciosas).
  static RoomPowerAction parse(String raw) {
    switch (raw) {
      case 'on':
        return RoomPowerAction.on;
      case 'off':
        return RoomPowerAction.off;
      default:
        throw FormatException('Accion de sala invalida: "$raw".');
    }
  }
}

/// Confirmacion del POST /room/power (202): la tarea programada fue
/// disparada, no completada. `task_name` es el nombre de la tarea de
/// Windows (Cauce_ON / Cauce_OFF).
class RoomPowerAccepted {
  const RoomPowerAccepted({required this.action, required this.taskName});

  final RoomPowerAction action;
  final String taskName;

  factory RoomPowerAccepted.fromJson(Map<String, dynamic> json) =>
      RoomPowerAccepted(
        action: RoomPowerAction.parse(json['action'] as String),
        taskName: json['task_name'] as String,
      );
}

/// Estado de una tarea programada (Cauce_ON o Cauce_OFF) segun el
/// Programador de Tareas del servidor. Nada de esto se persiste en la
/// BD: la fuente de verdad es el host.
class RoomTaskStatus {
  const RoomTaskStatus({
    required this.taskName,
    required this.running,
    this.lastRunTime,
    this.lastTaskResult,
    this.succeeded,
  });

  final String taskName;

  /// Hora local del servidor de la ultima ejecucion; null si la
  /// tarea nunca ha corrido.
  final DateTime? lastRunTime;

  /// Codigo de resultado de la ultima ejecucion (0 = exito).
  final int? lastTaskResult;

  /// La tarea esta ejecutandose ahora mismo.
  final bool running;

  /// Exito de la ultima ejecucion; null = la tarea nunca ha corrido.
  final bool? succeeded;

  factory RoomTaskStatus.fromJson(Map<String, dynamic> json) => RoomTaskStatus(
    taskName: json['task_name'] as String,
    lastRunTime: json['last_run_time'] == null
        ? null
        : DateTime.parse(json['last_run_time'] as String),
    lastTaskResult: (json['last_task_result'] as num?)?.toInt(),
    running: json['running'] as bool? ?? false,
    succeeded: json['succeeded'] as bool?,
  );

  /// Etiqueta corta para la UI del resultado de la ultima ejecucion.
  String get resultLabel {
    if (running) return 'Ejecutandose ahora';
    final ok = succeeded;
    if (ok == null) return 'Nunca ha corrido';
    if (ok) return 'Ultima ejecucion exitosa';
    return 'Ultima ejecucion fallida '
        '(codigo ${lastTaskResult ?? 'desconocido'})';
  }
}

/// Estado combinado de las tareas de encendido y apagado
/// (GET /room/power, 200).
class RoomPowerStatus {
  const RoomPowerStatus({required this.on, required this.off});

  final RoomTaskStatus on;
  final RoomTaskStatus off;

  factory RoomPowerStatus.fromJson(Map<String, dynamic> json) =>
      RoomPowerStatus(
        on: RoomTaskStatus.fromJson(json['on'] as Map<String, dynamic>),
        off: RoomTaskStatus.fromJson(json['off'] as Map<String, dynamic>),
      );

  /// Estado de la tarea correspondiente a una accion.
  RoomTaskStatus taskFor(RoomPowerAction action) =>
      action == RoomPowerAction.on ? on : off;
}
