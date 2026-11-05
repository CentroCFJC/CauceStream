import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:cauce_stream/main.dart';
import 'package:cauce_stream/models/playback_message.dart';
import 'package:cauce_stream/models/video_item.dart';
import 'package:cauce_stream/screens/auto_playback_screen.dart';
import 'package:cauce_stream/services/google_drive_service.dart';
import 'package:cauce_stream/services/playback_socket_service.dart';

/// Falso servicio Drive sin red: la pantalla arranca en modo screensaver
/// y se queda esperando (retryOnError: false) sin tocar la red.
class _FakeDriveService extends GoogleDriveService {
  @override
  Future<List<VideoItem>> listMediaInFolder(String folderId) async => [];
}

/// Plataforma de video falsa: no decodifica nada, solo informa el
/// tamaño (efectivo, ya rotado) del video asignado.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  _FakeVideoPlatform(this.videoSize);

  final Size videoSize;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 7;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    yield VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: videoSize,
    );
  }

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}

// PNG 1x1 válido (cuadrado).
final List<int> _squarePngBytes =
    base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Future<File> _writeTempFile(String name, List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('cauce_test');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file;
}

AssignmentMedia _media(String name, PlaybackMediaType type) => AssignmentMedia(
      name: name,
      mediaType: type,
      fileUrl: '/api/media/1/file',
      externalUrl: null,
    );

AssignmentMedia _mediaUrl(String name) => AssignmentMedia(
      name: name,
      mediaType: PlaybackMediaType.url,
      fileUrl: null,
      externalUrl: 'https://example.com/$name',
    );

Future<PlaybackApplier> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    CauceStreamApp(
      home: AutoPlaybackScreen(
        driveService: _FakeDriveService(),
        retryOnError: false,
      ),
    ),
  );
  await tester.pump();
  final state = tester.state<State<AutoPlaybackScreen>>(
    find.byType(AutoPlaybackScreen),
  );
  return state as PlaybackApplier;
}

Future<PlaybackApplier> _pumpScreenWithUrlBuilder(
  WidgetTester tester,
  UrlViewBuilder builder,
) async {
  await tester.pumpWidget(
    CauceStreamApp(
      home: AutoPlaybackScreen(
        driveService: _FakeDriveService(),
        retryOnError: false,
        urlViewBuilder: builder,
      ),
    ),
  );
  await tester.pump();
  final state = tester.state<State<AutoPlaybackScreen>>(
    find.byType(AutoPlaybackScreen),
  );
  return state as PlaybackApplier;
}

/// Vista falsa de un medio `url`: reporta el resultado de carga en el
/// primer frame posterior al montaje. `outcome == null` simula una
/// carga que nunca termina.
class _FakeUrlView extends StatefulWidget {
  const _FakeUrlView({
    required this.url,
    required this.onLoadResult,
    required this.outcome,
  });

  final Uri url;
  final void Function(bool displayed, String? error) onLoadResult;
  final bool? outcome;

  @override
  State<_FakeUrlView> createState() => _FakeUrlViewState();
}

class _FakeUrlViewState extends State<_FakeUrlView> {
  @override
  void initState() {
    super.initState();
    final outcome = widget.outcome;
    if (outcome != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onLoadResult(
            outcome,
            outcome ? null : 'ERR_CONNECTION_REFUSED',
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF003300),
      child: Center(child: Text('web:${widget.url}')),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  group('Imagen asignada', () {
    testWidgets('se muestra completa, centrada y sin recortar '
        '(BoxFit.contain sobre fondo negro)', (tester) async {
      final applier = await _pumpScreen(tester);

      // Tanto la creación del archivo como showImage hacen I/O real
      // (dart:io); en testWidgets ese I/O solo avanza dentro de runAsync.
      var shown = false;
      await tester.runAsync(() async {
        final file = await _writeTempFile('cuadrada.png', _squarePngBytes);
        shown = await applier.showImage(
            file, _media('cuadrada.png', PlaybackMediaType.image));
      });
      expect(shown, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain,
          reason: 'Un fit distinto de contain recorta o deforma la imagen.');

      // La caja de pintado ocupa toda la pantalla y el fondo es negro.
      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getSize(find.byType(Image)), screenSize);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.black);
    });
  });

  group('Video asignado', () {
    testWidgets('vertical (1080x1920) se muestra en vertical, '
        'completo y centrado (FittedBox contain)', (tester) async {
      VideoPlayerPlatform.instance = _FakeVideoPlatform(const Size(1080, 1920));

      final applier = await _pumpScreen(tester);

      // El archivo se escribe con dart:io real: dentro de runAsync.
      var shown = false;
      await tester.runAsync(() async {
        final file = await _writeTempFile('vertical.mp4', [0, 0, 0, 1]);
        shown = await applier
            .showVideo(file, _media('vertical.mp4', PlaybackMediaType.video));
      });
      expect(shown, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.contain,
          reason: 'cover recorta un video vertical en pantalla horizontal.');
      expect(fitted.alignment, Alignment.center);

      // El SizedBox interno conserva el tamaño efectivo del video:
      // la relación de aspecto no se fuerza a la de la pantalla.
      final videoBox = tester.widget<SizedBox>(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 1080 && w.height == 1920,
        ),
      );
      expect(videoBox.width, 1080);
      expect(videoBox.height, 1920);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.black);
    });

    testWidgets('horizontal (1920x1080) se muestra completo y '
        'centrado (FittedBox contain)', (tester) async {
      VideoPlayerPlatform.instance = _FakeVideoPlatform(const Size(1920, 1080));

      final applier = await _pumpScreen(tester);

      // El archivo se escribe con dart:io real: dentro de runAsync.
      var shown = false;
      await tester.runAsync(() async {
        final file = await _writeTempFile('horizontal.mp4', [0, 0, 0, 1]);
        shown = await applier.showVideo(
            file, _media('horizontal.mp4', PlaybackMediaType.video));
      });
      expect(shown, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.contain);

      final videoBox = tester.widget<SizedBox>(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 1920 && w.height == 1080,
        ),
      );
      expect(videoBox.width, 1920);
      expect(videoBox.height, 1080);
    });
  });

  group('URL asignada (WebView in-app)', () {
    testWidgets('showUrl confirma true cuando la página termina de cargar '
        'y la vista ocupa toda la pantalla', (tester) async {
      final applier = await _pumpScreenWithUrlBuilder(
        tester,
        (url, onResult) =>
            _FakeUrlView(url: url, onLoadResult: onResult, outcome: true),
      );

      final future = applier.showUrl(
        Uri.parse('https://example.com/pantalla'),
        _mediaUrl('pantalla'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(await future, isTrue);
      expect(find.byType(_FakeUrlView), findsOneWidget);
      expect(find.text('web:https://example.com/pantalla'), findsOneWidget);

      final screenSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getSize(find.byType(_FakeUrlView)), screenSize);
    });

    testWidgets('showUrl devuelve false cuando falla la carga del frame '
        'principal', (tester) async {
      final applier = await _pumpScreenWithUrlBuilder(
        tester,
        (url, onResult) =>
            _FakeUrlView(url: url, onLoadResult: onResult, outcome: false),
      );

      final future = applier.showUrl(
        Uri.parse('https://example.com/caida'),
        _mediaUrl('caida'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(await future, isFalse);
    });

    testWidgets('una orden posterior (showDefault) resuelve false el showUrl '
        'pendiente', (tester) async {
      final applier = await _pumpScreenWithUrlBuilder(
        tester,
        (url, onResult) =>
            _FakeUrlView(url: url, onLoadResult: onResult, outcome: null),
      );

      final urlFuture = applier.showUrl(
        Uri.parse('https://example.com/lenta'),
        _mediaUrl('lenta'),
      );
      await tester.pump();

      expect(await applier.showDefault(), isTrue);
      expect(await urlFuture, isFalse);
    });
  });
}
