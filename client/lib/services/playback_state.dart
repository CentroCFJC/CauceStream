/// Única fuente de verdad del medio activo, compartida por inyección
/// entre el servicio de playback (que la escribe) y el de heartbeat
/// (que la lee). Sin globales mutables ocultos.
///
/// `currentMediaId` es el Media.id que el reproductor CONFIRMÓ en
/// pantalla; null significa "sin medio válido reproduciéndose" y el
/// heartbeat simplemente omite `current_media` (el servidor guarda
/// "unknown"). Un ACK nunca escribe aquí.
class PlaybackState {
  int? _currentMediaId;

  int? get currentMediaId => _currentMediaId;

  /// Solo lo llama el servicio de playback cuando el reproductor
  /// confirma que el medio comenzó a mostrarse/reproducirse.
  void setPlaying(int mediaId) {
    _currentMediaId = mediaId;
  }

  /// El medio dejó de ser válido (asignación retirada o vuelta al
  /// comportamiento por defecto).
  void clear() {
    _currentMediaId = null;
  }
}
