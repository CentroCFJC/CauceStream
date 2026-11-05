import 'dart:async';

/// Puerta de confirmación de carga de un medio `url` en el WebView.
///
/// Resuelve UNA sola vez vía [onResult]:
/// - `true` cuando la página terminó de cargar (`onPageFinished`);
/// - `false` con mensaje cuando falla el frame principal
///   (`onWebResourceError` main frame), se agota el timeout o el WebView
///   se desmonta antes de terminar.
///
/// El `showUrl` del applier usa esto para devolver true solo cuando la
/// web quedó realmente en pantalla: si no, el servicio reporta
/// `playback.error display_failed` y el heartbeat conserva el último
/// medio confirmado. Puro (sin WebView): testeable sin plataforma.
class UrlLoadGate {
  UrlLoadGate({
    required Duration timeout,
    required void Function(bool displayed, String? error) onResult,
  })  : _onResult = onResult {
    _timer = Timer(
      timeout,
      () => settle(false, 'tiempo de carga agotado tras $timeout'),
    );
  }

  final void Function(bool displayed, String? error) _onResult;
  Timer? _timer;
  bool _settled = false;

  bool get isSettled => _settled;

  /// La página terminó de cargar: el medio queda confirmado en pantalla.
  void pageFinished() => settle(true, null);

  /// Falló la carga del frame principal (la página en sí no cargó).
  void mainFrameError(String description) => settle(false, description);

  void settle(bool displayed, String? error) {
    if (_settled) return;
    _settled = true;
    _timer?.cancel();
    _timer = null;
    _onResult(displayed, error);
  }

  /// Desmontaje antes de resolver: el resultado pendiente es "no
  /// mostrado", para no dejar colgado al `showUrl` que espera.
  void dispose() {
    if (!_settled) settle(false, 'WebView desmontado antes de cargar');
    _timer?.cancel();
    _timer = null;
  }
}
