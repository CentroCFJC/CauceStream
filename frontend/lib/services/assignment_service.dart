/// Servicio de asignaciones de contenido contra el backend Cauce.
///
/// Contratos reales:
/// - GET /api/assignments                  (permiso `content.view`)
/// - PUT /api/devices/{uid}/assignment     (permiso `content.manage`)
library;

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../models/assignment.dart';

class AssignmentService {
  AssignmentService({required ApiClient client}) : _client = client;

  final ApiClient _client;

  /// Todas las asignaciones vigentes (una por dispositivo), con el
  /// estado de sincronizacion que el servidor deriva de los
  /// heartbeats. El filtrado por dispositivo o medio se hace en
  /// memoria: una sola llamada sirve a ambas vistas.
  Future<List<Assignment>> getAssignments() async {
    final data = await _client.get(ApiConfig.assignmentsPath);
    return (data as List<dynamic>)
        .map((item) => Assignment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Crea o REEMPLAZA la asignacion vigente del dispositivo.
  ///
  /// Devuelve la asignacion con su `sync_status` inicial (`pending`
  /// casi siempre): el paso a `synchronized` lo hace el servidor
  /// cuando el dispositivo reporta reproducir el medio; la UI solo
  /// muestra lo que el backend responde.
  Future<Assignment> assignMedia(String deviceUid, int mediaId) async {
    final data = await _client.put(
      '${ApiConfig.devicesPath}/${Uri.encodeComponent(deviceUid)}/assignment',
      body: {'media_id': mediaId},
    );
    return Assignment.fromJson(data as Map<String, dynamic>);
  }
}
