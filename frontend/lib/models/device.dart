/// Modelos de dominio del frontend.
///
/// `Device` refleja el esquema `DeviceRead` del backend
/// (app/schemas/device.py): inventario registrado mas el estado que
/// el servidor deriva de los heartbeats (conectividad + estado
/// operativo activo/en espera).
library;

import 'package:flutter/material.dart';

import '../widgets/identity_widgets.dart';
import 'media.dart';

class Device {
  const Device({
    required this.id,
    required this.deviceUid,
    required this.name,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.ipAddress,
    this.macAddress,
    this.port,
    this.deviceState,
    this.currentMedia,
    this.payload,
    this.lastSeen,
    this.wsConnected = false,
  });

  final int id;

  /// Identificador estable del dispositivo (nombre expuesto por el SO).
  /// La IP puede cambiar; nunca se usa como identidad.
  final String deviceUid;
  final String name;
  final String type;
  final String? ipAddress;

  /// MAC para Wake-on-LAN del lado del servidor (app/power del backend).
  final String? macAddress;
  final int? port;

  /// Conectividad derivada del heartbeat: 'online' | 'offline'.
  final String status;

  /// Estado operativo reportado por el cliente: 'active' | 'idle' | null.
  final String? deviceState;

  /// Medio que el dispositivo reporta reproducir por heartbeat: el
  /// backend guarda el ID del medio (nunca el nombre), por eso la UI
  /// resuelve contra la biblioteca con [playingMedia].
  final String? currentMedia;

  /// Atributos dinamicos especificos del tipo de dispositivo
  /// (bateria, fuente de energia, etc.).
  final Map<String, dynamic>? payload;

  /// Ultimo heartbeat recibido por el servidor.
  final DateTime? lastSeen;

  /// Canal WebSocket de playback activo en el servidor. Independiente
  /// de [isOnline]: un dispositivo vivo puede no tener canal abierto, y
  /// en ese caso la asignacion de contenido le llega en la proxima
  /// reconexion. Default false (backends sin el campo).
  final bool wsConnected;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as int,
    deviceUid: json['device_uid'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    ipAddress: json['ip_address'] as String?,
    macAddress: json['mac_address'] as String?,
    port: json['port'] as int?,
    status: json['status'] as String? ?? 'offline',
    deviceState: json['device_state'] as String?,
    currentMedia: json['current_media'] as String?,
    payload: json['payload'] as Map<String, dynamic>?,
    lastSeen: json['last_seen'] == null
        ? null
        : DateTime.parse(json['last_seen'] as String),
    wsConnected: json['ws_connected'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  bool get isOnline => status == 'online';

  /// En espera (standby): conectividad confirmada por heartbeat pero
  /// el cliente reporta device_state = 'idle'.
  bool get isStandby => isOnline && deviceState == 'idle';

  /// Activo: heartbeat confirmado y no esta en espera. Un
  /// device_state nulo con conectividad confirmada cuenta como
  /// activo (el cliente no reporto estado operativo, pero esta vivo).
  bool get isActive => isOnline && !isStandby;

  /// Estado combinado para los chips de la UI:
  /// - Desconectado: sin heartbeat reciente (el servidor lo marca offline).
  /// - En espera: en linea pero en reposo (device_state = idle).
  /// - Activo: en linea y disponible (device_state = active o nulo).
  CauceStatus get cauceStatus {
    if (!isOnline) return CauceStatus.offline;
    if (isStandby) return CauceStatus.alert;
    return CauceStatus.active;
  }

  String get statusLabel {
    if (!isOnline) return 'Desconectado';
    if (isStandby) return 'En espera';
    return 'Activo';
  }

  /// Icono del tipo segun el vocabulario del formulario de registro
  /// (Nuevo Dispositivo): TV, Visor VR, Tablet, Raspberry Pi, PC y
  /// el generico para cualquier otro tipo.
  IconData get typeIcon {
    final t = type.toLowerCase();
    if (t.contains('vr') || t.contains('visor')) return Icons.view_in_ar;
    if (t.contains('tv')) return Icons.tv;
    if (t.contains('tablet')) return Icons.tablet;
    if (t.contains('raspberry')) return Icons.memory;
    if (t == 'pc' || t.contains('computador')) return Icons.computer;
    return Icons.category;
  }

  /// Tiempo transcurrido desde el ultimo heartbeat, en formato corto.
  /// null cuando el dispositivo nunca se ha comunicado.
  String? get relativeLastSeen {
    final seen = lastSeen;
    if (seen == null) return null;
    final elapsed = DateTime.now().difference(seen);
    if (elapsed.isNegative) return 'hace instantes';
    final seconds = elapsed.inSeconds;
    if (seconds < 60) return 'hace $seconds s';
    final minutes = elapsed.inMinutes;
    if (minutes < 60) return 'hace $minutes min';
    final hours = elapsed.inHours;
    if (hours < 24) return 'hace $hours h';
    return 'hace ${elapsed.inDays} d';
  }

  /// Id numerico del medio reportado; null si no hay reporte o el
  /// valor no es un id.
  int? get currentMediaId {
    final raw = currentMedia;
    if (raw == null) return null;
    return int.tryParse(raw.trim());
  }

  /// Subtitulo de tarjeta: el tipo del inventario. El medio en
  /// reproduccion se resuelve aparte con [playingLabel] porque
  /// requiere la biblioteca.
  String get subtitle => type;
}

/// Medio de la biblioteca que el dispositivo reporta reproducir: el
/// heartbeat reporta el ID del medio, no su nombre, asi que la
/// resolucion contra la biblioteca devuelve el [Media] completo
/// (nombre y tipo). null cuando el dispositivo no reporta medio o
/// la biblioteca no lo tiene cargado.
Media? playingMedia(Device device, Iterable<Media> media) {
  final id = device.currentMediaId;
  if (id == null) return null;
  for (final m in media) {
    if (m.id == id) return m;
  }
  return null;
}

/// Dispositivo detectado por el autodescubrimiento, aun no registrado.
///
/// Solo identidad de red y estado operativo: el autodescubrimiento no
/// expone atributos dinamicos (`payload`) ni otros detalles del
/// cliente.
class PendingDevice {
  const PendingDevice({
    required this.deviceUid,
    this.ipAddress,
    this.deviceState,
  });

  final String deviceUid;
  final String? ipAddress;
  final String? deviceState;

  factory PendingDevice.fromJson(Map<String, dynamic> json) => PendingDevice(
    deviceUid: json['device_uid'] as String,
    ipAddress: json['ip_address'] as String?,
    deviceState: json['device_state'] as String?,
  );

  String get stateLabel {
    switch (deviceState) {
      case 'active':
        return 'Activo';
      case 'idle':
        return 'En espera';
      default:
        return '';
    }
  }
}
