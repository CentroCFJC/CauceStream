import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'controllers/connectivity_controller.dart';
import 'controllers/devices_controller.dart';
import 'controllers/media_library_controller.dart';
import 'controllers/room_controller.dart';
import 'core/config/api_config.dart';
import 'core/network/api_client.dart';
import 'core/theme/cauce_theme.dart';
import 'services/assignment_service.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/device_service.dart';
import 'services/media_service.dart';
import 'services/room_service.dart';
import 'services/thumbnail_service.dart';
import 'services/user_service.dart';
import 'session/session_controller.dart';
import 'session/token_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = ApiClient(baseUrl: ApiConfig.apiBaseUrl);
  final session = SessionController(
    storage: TokenStorage(),
    authService: AuthService(client: apiClient),
    userService: UserService(client: apiClient),
    apiClient: apiClient,
  );
  final devices = DevicesController(
    service: DeviceService(client: apiClient),
    assignmentService: AssignmentService(client: apiClient),
  );
  final mediaService = MediaService(client: apiClient);
  final mediaLibrary = MediaLibraryController(
    service: mediaService,
    thumbnails: ThumbnailService(service: mediaService),
  );

  // Encendido/apagado maestro de la sala: endpoint TEMPORAL
  // (backend/docs/room_power_temporal.md), aislado de DeviceService.
  final room = RoomController(service: RoomService(client: apiClient));

  // Indicador LAN: sondeo del endpoint de salud del servidor activo
  // (local o Tailscale, segun ApiConfig).
  final connectivity = ConnectivityController(service: ConnectivityService());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: devices),
        ChangeNotifierProvider.value(value: mediaLibrary),
        ChangeNotifierProvider.value(value: connectivity),
        ChangeNotifierProvider.value(value: room),
      ],
      child: const CauceApp(),
    ),
  );
}

/// Aplicacion CauceStream.
class CauceApp extends StatelessWidget {
  const CauceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CauceStream',
      debugShowCheckedModeBanner: false,
      theme: CauceTheme.light,
      home: const SessionGate(),
    );
  }
}
