import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../models/video_item.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem video;

  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const Duration _controlsAutoHide = Duration(seconds: 5);
  Timer? _hideControlsTimer;
  bool _hasPopped = false;

  void _showControlsWithTimer() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(_controlsAutoHide, () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.video.type == 'video') {
      if (Platform.isAndroid) {
        _initAndroidPlayer();
      }
    } else {
      setState(() => _initialized = true);
    }
  }

  Future<void> _initAndroidPlayer() async {
    while (_retryCount < _maxRetries) {
      try {
        debugPrint('[CAUCE] Intento ${_retryCount + 1}/$_maxRetries — Cargando: ${widget.video.fileUrl}');
        final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.video.fileUrl));
        _controller = ctrl;
        await ctrl.initialize();
        ctrl.setLooping(true);
        ctrl.addListener(_onPlayerStateChanged);
        if (!mounted) return;
        debugPrint('[CAUCE] Video inicializado correctamente');
        setState(() => _initialized = true);
        ctrl.play();
        return;
      } catch (e) {
        debugPrint('[CAUCE] Error en intento ${_retryCount + 1}: $e');
        _controller?.dispose();
        _controller = null;
        _retryCount++;
        if (!mounted) return;
        if (_retryCount < _maxRetries) {
          final delay = Duration(seconds: _retryCount * 2);
          debugPrint('[CAUCE] Reintentando en ${delay.inSeconds}s...');
          await Future.delayed(delay);
        } else {
          debugPrint('[CAUCE] Todos los intentos fallaron');
          _showError(
            'No se pudo reproducir el video después de $_maxRetries intentos.\n\n'
            'Esto puede deberse a un problema con el decoder de video del televisor '
            'o la conexión a Google Drive.\n\n'
            'Detalle: $e',
          );
        }
      }
    }
  }

  void _onPlayerStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onPlayerStateChanged);
    _controller?.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.gameButtonB ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.mediaStop) {
      if (!_hasPopped && Navigator.canPop(context)) {
        _hasPopped = true;
        Navigator.pop(context);
      }
      return KeyEventResult.handled;
    }

    if (!_initialized) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
        event.logicalKey == LogicalKeyboardKey.select) {
      _showControlsWithTimer();
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final pos = _controller!.value.position;
      final newPos = Duration(milliseconds: (pos.inMilliseconds - 5000).clamp(0, _controller!.value.duration.inMilliseconds));
      _controller!.seekTo(newPos);
      _showControlsWithTimer();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final pos = _controller!.value.position;
      final newPos = Duration(milliseconds: (pos.inMilliseconds + 5000).clamp(0, _controller!.value.duration.inMilliseconds));
      _controller!.seekTo(newPos);
      _showControlsWithTimer();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (!_showControls) _showControlsWithTimer();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;

    if (video.type == 'image' || video.type == 'gif') {
      return _buildImageViewer();
    }

    if (video.type == 'pdf') {
      return _buildPdfFallback();
    }

    if (Platform.isAndroid) {
      return PopScope(
        canPop: !_hasPopped,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _hasPopped = true;
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0A1628),
          body: Focus(
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: _initialized ? _buildPlayer() : _buildLoading(),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: _buildDesktopFallback(),
    );
  }

  Widget _buildDesktopFallback() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tv, color: Colors.white54, size: 100),
          const SizedBox(height: 32),
          const Text(
            'Display disponible solo en Android TV',
            style: TextStyle(color: Colors.white70, fontSize: 22),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            widget.video.name,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Abrir en el navegador'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            ),
          ),
            const SizedBox(height: 20),
            TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Volver al contenido',
              style: TextStyle(color: Colors.white54, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.video.fileUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF1565C0)),
          SizedBox(height: 16),
          Text(
            'Preparando video...',
            style: TextStyle(color: Colors.white70, fontSize: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            if (_showControls) {
              _hideControlsTimer?.cancel();
              setState(() => _showControls = false);
            } else {
              _showControlsWithTimer();
            }
          },
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),
        if (_showControls) _buildControlsOverlay(),
      ],
    );
  }

  Widget _buildControlsOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: const Color(0xFF0A1628).withAlpha(200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Color(0xFF1565C0),
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _ControlButton(
                  icon: _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  onPressed: () {
                    _showControlsWithTimer();
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  },
                ),
                const SizedBox(width: 24),
                Text(
                  _formatDuration(_controller!.value.position),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const Spacer(),
                Text(
                  _formatDuration(_controller!.value.duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildImageViewer() {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                 event.logicalKey == LogicalKeyboardKey.gameButtonB ||
                 event.logicalKey == LogicalKeyboardKey.goBack ||
                 event.logicalKey == LogicalKeyboardKey.backspace)) {
              if (Navigator.canPop(context)) Navigator.pop(context);
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.select ||
                 event.logicalKey == LogicalKeyboardKey.enter)) {
              if (Navigator.canPop(context)) Navigator.pop(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Center(
            child: Image.network(
              widget.video.fileUrl,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1565C0)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPdfFallback() {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                 event.logicalKey == LogicalKeyboardKey.gameButtonB ||
                 event.logicalKey == LogicalKeyboardKey.goBack ||
                 event.logicalKey == LogicalKeyboardKey.backspace)) {
              if (Navigator.canPop(context)) Navigator.pop(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.picture_as_pdf, color: Color(0xFF1565C0), size: 100),
                const SizedBox(height: 24),
                Text(
                  widget.video.name,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Documento PDF',
                  style: TextStyle(color: Colors.white54, fontSize: 20),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Abrir en el navegador'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Volver al contenido',
                    style: TextStyle(color: Colors.white54, fontSize: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    _retryCount = 0;
    setState(() => _initialized = false);
    _initAndroidPlayer();
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Error', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _retry();
            },
            child: const Text('Reintentar', style: TextStyle(color: Color(0xFF1565C0))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Volver', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ControlButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 40),
        onPressed: onPressed,
        splashRadius: 28,
      ),
    );
  }
}
