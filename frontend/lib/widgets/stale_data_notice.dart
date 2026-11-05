/// Aviso de datos caducados compartido por las pantallas de
/// dispositivos: el sondeo del servidor lleva fallando y lo mostrado es
/// una foto del ultimo sondeo exitoso.
///
/// NO cambia el estado de ningun dispositivo (isOnline/wsConnected se
/// respetan tal cual): solo declara la edad del conocimiento, para que
/// un chip "Activo" congelado nunca parezca un estado actual.

import 'package:flutter/material.dart';

import '../core/theme/cauce_colors.dart';
import '../core/theme/cauce_theme.dart';

class StaleDataNotice extends StatelessWidget {
  const StaleDataNotice({super.key, required this.fetchedAt});

  /// Momento del ultimo sondeo exitoso del controlador.
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final fetched = fetchedAt;
    final label = fetched == null
        ? 'sin datos recientes'
        : () {
            final age = DateTime.now().difference(fetched);
            return age.inMinutes >= 1
                ? 'hace ${age.inMinutes} min'
                : 'hace ${age.inSeconds} s';
          }();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CauceColors.peachSurfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: CauceColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sin respuesta del servidor: el estado mostrado es de '
              '$label y puede estar desactualizado.',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 11,
                height: 1.3,
                color: CauceColors.peachOnSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
