import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../config/constants.dart';
import '../models/playback_message.dart';
import '../models/video_item.dart';
import '../services/google_drive_service.dart';
import '../services/playback_socket_service.dart';
import '../widgets/kiosk_web_view.dart';
import '../widgets/river_loading_indicator.dart';

/// Vista inyectable para un medio `url` (pruebas). Firma idéntica a la
/// que usa la pantalla para montar el [KioskWebView] real.
typedef UrlViewBuilder = Widget Function(
  Uri url,
  void Function(bool displayed, String? error) onLoadResult,
);

class AutoPlaybackScreen extends StatefulWidget {
  final GoogleDriveService? driveService;
  final PlaybackSocketService? playbackService;
  final bool retryOnError;

  /// En producción es null: el medio `url` se monta con [KioskWebView]
  /// (WebView in-app) o, en plataformas sin WebView in-app, se abre con
  /// el navegador del sistema. En pruebas permite sustituir la vista.
  final UrlViewBuilder? urlViewBuilder;

  const AutoPlaybackScreen({
    super.key,
    this.driveService,
    this.playbackService,
    this.retryOnError = true,
    this.urlViewBuilder,
  });

  @override
  State<AutoPlaybackScreen> createState() => _AutoPlaybackScreenState();
}

/// Qué hay en pantalla ahora mismo.
enum _DisplayMode {
  /// Screensaver de Google Drive en bucle (comportamiento por defecto,
  /// sin asignación vigente del servidor).
  screensaver,

  /// Video asignado por Cauce reproduciéndose en bucle.
  assignedVideo,

  /// Imagen asignada por Cauce en pantalla.
  assignedImage,

  /// Medio `url` asignado por Cauce: WebView in-app a pantalla completa
  /// (o navegador externo en plataformas sin WebView in-app).
  assignedUrl,

  /// Documento PDF asignado por Cauce (render nativo con pdfx).
  assignedPdf,
}

class _AutoPlaybackScreenState extends State<AutoPlaybackScreen>
    implements PlaybackApplier {
  late final GoogleDriveService _driveService;
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _statusMessage;
  int _loadRetryCount = 0;
  int _initRetryCount = 0;
  bool _disposed = false;
  bool _recovering = false;
  Timer? _watchdogTimer;
  Duration _lastWatchdogPosition = Duration.zero;

  _DisplayMode _mode = _DisplayMode.screensaver;

  /// Generación de visualización: cada orden del servicio la incrementa;
  /// los bucles y awaits pendientes de una generación anterior se
  /// abortan. Evita que dos órdenes controlen el reproductor a la vez.
  int _displayGen = 0;

  File? _assignedVideoFile;
  File? _assignedImageFile;
  Uri? _assignedUrl;
  File? _assignedPdfFile;
  PdfController? _pdfController;
  String? _assignedMediaName;

  /// Completers de carga pendientes por URL asignada (modo `url` con
  /// WebView in-app): el `showUrl` espera a que la web confirme en
  /// pantalla antes de devolver true.
  final Map<String, Completer<bool>> _urlLoadCompleters = {};

  /// WebView in-app solo existe en Android/iOS (webview_flutter). En el
  /// resto de plataformas el medio `url` se abre con el navegador del
  /// sistema vía url_launcher.
  bool get _inAppWebViewSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _driveService = widget.driveService ?? GoogleDriveService();
    _loadAndPlay(_displayGen);
    // El servicio global (WS de playback) nos drive mediante este
    // applier; sin servicio la pantalla funciona como screensaver.
    widget.playbackService?.attach(this);
  }

  // --- PlaybackApplier (órdenes del WS de Cauce) ---

  @override
  Future<bool> showImage(File file, AssignmentMedia media) async {
    final gen = ++_displayGen;
    try {
      // Confirma que la imagen decodifica ANTES de quitar el medio
      // actual de pantalla.
      if (!mounted || _disposed) return false;
      await precacheImage(FileImage(File(file.path)), context);
      if (_disposed || gen != _displayGen) return false;
      _stopVideo();
      _failPendingUrlLoads();
      _disposePdf();
      setState(() {
        _mode = _DisplayMode.assignedImage;
        _assignedImageFile = file;
        _assignedMediaName = media.name;
        _initialized = false;
      });
      debugPrint('[CAUCE] Imagen asignada en pantalla: ${media.name}');
      return true;
    } catch (e) {
      debugPrint('[CAUCE] No se pudo mostrar la imagen: $e');
      return false;
    }
  }

  @override
  Future<bool> showVideo(File file, AssignmentMedia media) async {
    final gen = ++_displayGen;
    try {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      await ctrl.setLooping(true);
      await ctrl.setVolume(1.0);
      await ctrl.play();
      if (_disposed || gen != _displayGen) {
        await ctrl.dispose();
        return false;
      }
      _failPendingUrlLoads();
      _disposePdf();
      _adoptVideoController(ctrl);
      setState(() {
        _mode = _DisplayMode.assignedVideo;
        _assignedVideoFile = file;
        _assignedMediaName = media.name;
        _initialized = true;
      });
      debugPrint('[CAUCE] Video asignado reproduciéndose: ${media.name}');
      return true;
    } catch (e) {
      debugPrint('[CAUCE] No se pudo reproducir el video asignado: $e');
      return false;
    }
  }

  @override
  Future<bool> showUrl(Uri url, AssignmentMedia media) async {
    final gen = ++_displayGen;
    if (_disposed || gen != _displayGen) return false;
    _stopVideo();

    if (!_inAppWebViewSupported) {
      // Plataformas sin WebView in-app (Windows/Linux/web): la URL se
      // abre con el navegador del sistema como aplicación externa
      // (estándar de la plataforma); aquí solo se muestra la dirección.
      try {
        final launched = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          debugPrint('[CAUCE] No se pudo abrir la URL externa: $url');
          return false;
        }
        if (_disposed || gen != _displayGen) return false;
        setState(() {
          _mode = _DisplayMode.assignedUrl;
          _assignedUrl = url;
          _assignedMediaName = media.name;
          _initialized = false;
        });
        debugPrint('[CAUCE] Medio url abierto en navegador externo: $url');
        return true;
      } catch (e) {
        debugPrint('[CAUCE] Error abriendo la URL externa: $e');
        return false;
      }
    }

    // WebView in-app (Android/iOS): true SOLO cuando la página terminó
    // de cargar en pantalla (UrlLoadGate dentro de KioskWebView).
    final completer = Completer<bool>();
    _urlLoadCompleters[url.toString()] = completer;
    setState(() {
      _mode = _DisplayMode.assignedUrl;
      _assignedUrl = url;
      _assignedMediaName = media.name;
      _initialized = false;
    });
    final displayed = await completer.future;
    _urlLoadCompleters.remove(url.toString());
    if (_disposed || gen != _displayGen) return false;
    debugPrint(displayed
        ? '[CAUCE] Medio url en pantalla: $url'
        : '[CAUCE] Medio url NO se pudo mostrar: $url');
    return displayed;
  }

  /// PDF asignado: se descarga como image/video y se renderiza con
  /// pdfx. true SOLO cuando el documento terminó de cargar en pantalla.
  @override
  Future<bool> showPdf(File file, AssignmentMedia media) async {
    final gen = ++_displayGen;
    if (_disposed || gen != _displayGen) return false;
    _stopVideo();
    _failPendingUrlLoads();
    _disposePdf();
    try {
      final document = await PdfDocument.openFile(file.path);
      if (_disposed || gen != _displayGen) {
        await document.close();
        return false;
      }
      final controller = PdfController(document: Future.value(document));
      _pdfController = controller;
      setState(() {
        _mode = _DisplayMode.assignedPdf;
        _assignedPdfFile = file;
        _assignedMediaName = media.name;
        _initialized = false;
      });
      final loaded = await _waitPdfLoaded(controller);
      if (_disposed || gen != _displayGen) return false;
      debugPrint(
        loaded
            ? '[CAUCE] PDF en pantalla: ${file.path}'
            : '[CAUCE] PDF no terminó de cargar: ${file.path}',
      );
      return loaded;
    } catch (e) {
      debugPrint('[CAUCE] No se pudo abrir el PDF ${file.path}: $e');
      return false;
    }
  }

  /// Espera a que el PdfView termine de cargar (o falle) con timeout.
  Future<bool> _waitPdfLoaded(PdfController controller) async {
    final state = controller.loadingState;
    if (state.value == PdfLoadingState.success) return true;
    if (state.value == PdfLoadingState.error) return false;
    final completer = Completer<bool>();
    void listener() {
      final s = state.value;
      if (s == PdfLoadingState.success || s == PdfLoadingState.error) {
        if (!completer.isCompleted) {
          completer.complete(s == PdfLoadingState.success);
        }
      }
    }

    state.addListener(listener);
    try {
      return await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => false,
      );
    } finally {
      state.removeListener(listener);
    }
  }

  void _disposePdf() {
    _pdfController?.dispose();
    _pdfController = null;
    _assignedPdfFile = null;
  }

  @override
  Future<bool> showDefault() async {
    if (_disposed) return false;
    // Ya estamos en el modo por defecto con el bucle vivo: nada que
    // hacer (el bucle del screensaver sigue su curso).
    if (_mode == _DisplayMode.screensaver) return true;
    final gen = ++_displayGen;
    _stopVideo();
    _failPendingUrlLoads();
    _disposePdf();
    setState(() {
      _mode = _DisplayMode.screensaver;
      _initialized = false;
      _statusMessage = null;
    });
    _loadAndPlay(gen);
    return true;
  }

  // --- Screensaver (comportamiento por defecto, Google Drive) ---

  Future<void> _loadAndPlay(int gen) async {
    while (!_disposed) {
      if (gen != _displayGen) return;
      try {
        _setStatus('Cargando video...');
        final items = await _driveService.listMediaInFolder(
          AppConfig.playbackFolderId,
        );
        if (_disposed || gen != _displayGen) return;

        final video = items.cast<VideoItem?>().firstWhere(
              (item) =>
                  item != null &&
                  item.type == 'video' &&
                  item.name.toLowerCase() == 'screensaver',
              orElse: () => null,
            );

        if (video == null) {
          debugPrint('[CAUCE] No se encontró screensaver.mp4 en la carpeta');
          _setStatus('Buscando screensaver.mp4...');
          if (!widget.retryOnError) return;
          await _waitSeconds(10);
          continue;
        }

        debugPrint('[CAUCE] Video seleccionado: ${video.name} (${video.id})');
        final cacheFile = await _cacheVideo(video);
        if (_disposed || gen != _displayGen) return;
        await _initVideoController(cacheFile, gen);
        return;
      } catch (e) {
        debugPrint('[CAUCE] Error al obtener el video: $e');
        _loadRetryCount++;
        _setStatus('Error de conexión. Reintentando...');
        if (!widget.retryOnError) return;
        await _waitSeconds(math.min(5 + _loadRetryCount * 2, 30));
      }
    }
  }

  Future<File> _cacheVideo(VideoItem video) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'screensaver_${video.id}.mp4';
    final file = File('${dir.path}/$fileName');

    if (await file.exists() && await file.length() > 0) {
      debugPrint('[CAUCE] Usando video en caché: ${file.path}');
      return file;
    }

    _setStatus('Descargando video...');
    debugPrint('[CAUCE] Descargando video a caché...');
    await _driveService.downloadFile(video.fileUrl, file);
    debugPrint(
        '[CAUCE] Descarga completada: ${file.path} (${await file.length()} bytes)');
    return file;
  }

  /// Inicializa y reproduce [file] en bucle, con reintentos. Retorna
  /// cuando la reproducción está activa (o agotadas las opciones sin
  /// retryOnError). Si la generación cambia, el controlador nuevo se
  /// descarta y el de pantalla queda como esté.
  Future<void> _initVideoController(File file, int gen) async {
    while (!_disposed) {
      if (gen != _displayGen) return;
      try {
        _setStatus('Preparando video...');
        final ctrl = VideoPlayerController.file(file);
        await ctrl.initialize();
        await ctrl.setLooping(true);
        await ctrl.setVolume(1.0);

        if (_disposed || gen != _displayGen) {
          await ctrl.dispose();
          return;
        }

        _adoptVideoController(ctrl);
        setState(() => _initialized = true);
        await ctrl.play();
        _startWatchdog();
        return;
      } catch (e) {
        debugPrint('[CAUCE] Error al inicializar el reproductor: $e');
        _initRetryCount++;
        _setStatus('Error al reproducir. Reintentando...');
        if (!widget.retryOnError) return;
        await _waitSeconds(math.min(2 + _initRetryCount * 2, 30));
      }
    }
  }

  /// Sustituye el controlador vigente por [ctrl] (listener + dispose
  /// del anterior). El cambio atómico evita que una orden fallida deje
  /// la pantalla sin reproductor.
  void _adoptVideoController(VideoPlayerController ctrl) {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = ctrl;
    ctrl.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    if (ctrl.value.hasError) {
      debugPrint(
          '[CAUCE] Error en reproducción: ${ctrl.value.errorDescription}');
      _scheduleRecovery();
      return;
    }

    // Respaldo por si setLooping no funcionara en algún dispositivo.
    if (!ctrl.value.isPlaying &&
        ctrl.value.position >= ctrl.value.duration) {
      ctrl.seekTo(Duration.zero);
      ctrl.play();
    }
  }

  void _scheduleRecovery() {
    if (_recovering || _disposed) return;
    _recovering = true;
    _stopWatchdog();
    _setStatus('Reconectando video...');
    Future.microtask(() async {
      try {
        if (_disposed) return;
        final gen = _displayGen;
        _initRetryCount = 0;
        if (_mode == _DisplayMode.assignedVideo && _assignedVideoFile != null) {
          // El archivo ya está en caché: reintentar solo el reproductor.
          await _initVideoController(_assignedVideoFile!, gen);
        } else if (_mode == _DisplayMode.screensaver) {
          await _loadAndPlay(gen);
        }
        // Imágenes y url no tienen reproductor que recuperar.
      } finally {
        _recovering = false;
      }
    });
  }

  void _startWatchdog() {
    _stopWatchdog();
    _lastWatchdogPosition = _controller?.value.position ?? Duration.zero;
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_disposed) return;
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized) return;

      if (ctrl.value.hasError) {
        _scheduleRecovery();
        return;
      }

      if (ctrl.value.isPlaying &&
          !ctrl.value.isBuffering &&
          ctrl.value.position == _lastWatchdogPosition) {
        debugPrint('[CAUCE] Reproducción estancada. Reconectando...');
        _scheduleRecovery();
        return;
      }

      _lastWatchdogPosition = ctrl.value.position;
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Retira el video actual de pantalla y libera su controlador.
  void _stopVideo() {
    _stopWatchdog();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controller = null;
    _initialized = false;
  }

  void _setStatus(String message) {
    if (mounted && !_disposed) {
      setState(() => _statusMessage = message);
    }
  }

  Future<void> _waitSeconds(int seconds) async {
    await Future.delayed(Duration(seconds: seconds));
  }

  @override
  void dispose() {
    widget.playbackService?.detach(this);
    _disposed = true;
    _failPendingUrlLoads();
    _disposePdf();
    _stopWatchdog();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _driveService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: switch (_mode) {
          _DisplayMode.assignedImage => _buildAssignedImage(),
          _DisplayMode.assignedUrl => _buildAssignedUrl(),
          _DisplayMode.assignedPdf => _buildAssignedPdf(),
          _ => _initialized && _controller != null
              ? _buildPlayer()
              : _buildLoading(),
        },
      ),
    );
  }

  Widget _buildPlayer() {
    return IgnorePointer(
      child: SizedBox.expand(
        child: FittedBox(
          // contain: conserva la relación de aspecto real del video
          // (incluida la rotación de metadatos ya resuelta por el
          // controlador) sin recortar ni deformar; el hueco restante
          // queda sobre el fondo negro del Scaffold.
          fit: BoxFit.contain,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }

  Widget _buildAssignedImage() {
    final file = _assignedImageFile;
    if (file == null) return _buildLoading();
    return IgnorePointer(
      child: SizedBox.expand(
        child: Image.file(
          file,
          // contain: la imagen completa, centrada y sin recortes ni
          // deformaciones para cualquier relación de aspecto.
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('[CAUCE] Error decodificando la imagen: $error');
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }

  /// Medio `url`: WebView in-app a pantalla completa cuando la plataforma
  /// lo soporta (Android/iOS, p. ej. el iFFALCON G09 con Android 12);
  /// en el resto la página ya se abrió en el navegador del sistema y aquí
  /// solo se muestra la dirección.
  Widget _buildAssignedUrl() {
    final url = _assignedUrl;
    if (url == null) return _buildLoading();
    final customBuilder = widget.urlViewBuilder;
    final Widget child;
    if (customBuilder != null) {
      child = KeyedSubtree(
        key: ValueKey('url-view:$url'),
        child: customBuilder(url, (ok, _) => _completeUrlLoad(url, ok)),
      );
    } else if (_inAppWebViewSupported) {
      child = KioskWebView(
        key: ValueKey('kiosk-web-view:$url'),
        initialUrl: url,
        onLoadResult: (ok, _) => _completeUrlLoad(url, ok),
      );
    } else {
      child = _buildAssignedUrlText(url);
    }
    return SizedBox.expand(child: child);
  }

  /// Medio `pdf`: render nativo a pantalla completa (pdfx). El D-pad
  /// del control navega el PageView; sin interacción queda en la página 1.
  Widget _buildAssignedPdf() {
    final controller = _pdfController;
    if (controller == null) return _buildLoading();
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black,
        child: PdfView(
          key: ValueKey('pdf-view:${_assignedPdfFile?.path}'),
          controller: controller,
        ),
      ),
    );
  }

  void _completeUrlLoad(Uri url, bool displayed) {
    final completer = _urlLoadCompleters[url.toString()];
    if (completer != null && !completer.isCompleted) {
      completer.complete(displayed);
    }
  }

  /// Una orden nueva (imagen/video/modo por defecto) deja inválidas las
  /// cargas de URL pendientes: sus `showUrl` deben resolver false.
  void _failPendingUrlLoads() {
    for (final completer in _urlLoadCompleters.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _urlLoadCompleters.clear();
  }

  Widget _buildAssignedUrlText(Uri url) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _assignedMediaName ?? 'Medio asignado',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            url.toString(),
            style: const TextStyle(color: Colors.white70, fontSize: 22),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    final size = MediaQuery.of(context).size;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF1565C0),
          ),
          SizedBox(height: size.height * 0.04),
          Text(
            _statusMessage ?? 'Cargando video...',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 20,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: size.height * 0.04),
          const RiverLoadingIndicator(
            width: 240,
            height: 12,
          ),
        ],
      ),
    );
  }
}
