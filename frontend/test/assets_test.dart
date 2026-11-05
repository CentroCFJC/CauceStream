// Verifica que las claves de assets declaradas en pubspec.yaml
// (incluidas las que contienen espacios) cargan correctamente.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assetKeys = [
    'assets/logo_completo.png',
    'assets/logo_iso.png',
    'assets/decorations/tercios bajos -01.png',
    'assets/decorations/tercios bajos CAUCE-07.png',
    'assets/Iconos_Dispositivos/icono 1.png',
    'assets/Iconos_Dispositivos/icono 2.png',
    'assets/Iconos_Dispositivos/icono 3.png',
    'assets/Iconos_Dispositivos/icono 4.png',
    'assets/Iconos_Dispositivos/icono 5.png',
    'assets/Iconos_Dispositivos/icono 6.png',
    'assets/fonts/Space_Grotesk/static/SpaceGrotesk-Bold.ttf',
    'assets/fonts/Plus_Jakarta_Sans/static/PlusJakartaSans-Regular.ttf',
  ];

  test('los assets y fuentes referenciados por la app existen', () async {
    for (final key in assetKeys) {
      final data = await rootBundle.load(key);
      expect(data.lengthInBytes, greaterThan(0), reason: key);
    }
  });
}
