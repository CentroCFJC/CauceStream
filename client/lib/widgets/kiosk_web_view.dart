import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/url_load_gate.dart';

/// WebView in-app a pantalla completa para los medios `url` que Cauce
/// asigna al dispositivo.
///
/// - Sin capas de bloqueo del control: el WebView recibe nativamente el
///   D-pad del control (foco/scroll) y los gestos táctiles; no se
///   intercepta ninguna entrada.
/// - JavaScript habilitado (las webs modernas lo exigen), zoom
///   deshabilitado y fondo negro mientras carga.
/// - Reporta una sola vez vía [onLoadResult] si la página quedó en
///   pantalla (true) o no (false + motivo), vía [UrlLoadGate].
class KioskWebView extends StatefulWidget {
  const KioskWebView({
    super.key,
    required this.initialUrl,
    required this.onLoadResult,
    this.loadTimeout = const Duration(seconds: 30),
  });

  final Uri initialUrl;
  final Duration loadTimeout;
  final void Function(bool displayed, String? error) onLoadResult;

  @override
  State<KioskWebView> createState() => _KioskWebViewState();
}

class _KioskWebViewState extends State<KioskWebView> {
  late final WebViewController _controller;
  late final UrlLoadGate _gate;

  @override
  void initState() {
    super.initState();
    _gate = UrlLoadGate(
      timeout: widget.loadTimeout,
      onResult: widget.onLoadResult,
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _gate.pageFinished(),
          onWebResourceError: (error) {
            // Solo falla la asignación si no cargó la página en sí;
            // errores de subrecursos (iconos, anuncios...) no abortan.
            if (error.isForMainFrame ?? false) {
              _gate.mainFrameError(error.description);
            }
          },
        ),
      );
    unawaited(_controller.loadRequest(widget.initialUrl));
  }

  @override
  void dispose() {
    _gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: WebViewWidget(controller: _controller));
  }
}
