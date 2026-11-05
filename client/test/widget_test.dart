import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:cauce_stream/main.dart';
import 'package:cauce_stream/models/video_item.dart';
import 'package:cauce_stream/screens/auto_playback_screen.dart';
import 'package:cauce_stream/services/google_drive_service.dart';
import 'package:cauce_stream/widgets/river_loading_indicator.dart';

class _FakeDriveService extends GoogleDriveService {
  @override
  Future<List<VideoItem>> listMediaInFolder(String folderId) async {
    return [
      VideoItem(
        id: 'v1',
        name: 'Otro video',
        fileUrl: 'https://example.com/otro.mp4',
        type: 'video',
      ),
      VideoItem(
        id: 'v2',
        name: 'screensaver',
        fileUrl: 'https://example.com/screensaver.mp4',
        type: 'video',
      ),
    ];
  }
}

void main() {
  testWidgets('Inicia en la pantalla de reproducción automática', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: '.env');

    await tester.pumpWidget(
      CauceStreamApp(
        home: AutoPlaybackScreen(
          driveService: _FakeDriveService(),
          retryOnError: false,
        ),
      ),
    );

    expect(find.byType(AutoPlaybackScreen), findsOneWidget);
    expect(find.byType(RiverLoadingIndicator), findsOneWidget);
  });
}
