/// Actividades y alertas (solo interfaz).
///
/// Fase 1: composicion de actividades_y_alertas_cauce con datos
/// estaticos. Sin consultas al backend ni gestion funcional de
/// actividades.
library;

import 'package:flutter/material.dart';

import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../data/demo_data.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/organic_background.dart';

class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key});

  void _notAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'El registro de actividades se consultara a la API en una fase posterior.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(color: CauceColors.peachSurface),
        const OrganicBackground(
          topRight: false,
          bottomLeft: true,
          baseColor: CauceColors.peachSurface,
        ),
        Column(
          children: [
            // Mismo encabezado compartido que Dispositivos y
            // Biblioteca: coherencia visual entre pestanas.
            TabHeader(
              title: 'Actividad',
              onAvatarTap: () => Navigator.of(context).pushNamed('/profile'),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SummaryCard(),
                    const SizedBox(height: 16),
                    const _SearchAndFilters(),
                    const SizedBox(height: 16),
                    _EventList(onAction: () => _notAvailable(context)),
                    const SizedBox(height: 24),
                    _LoadMoreButton(onAction: () => _notAvailable(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CauceColors.peachSurfaceContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
        ],
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(
                Icons.monitor_heart,
                size: 20,
                color: CauceColors.creamPrimary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Actividad en Vivo de Sala',
                  style: TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CauceColors.peachOnSurface,
                  ),
                ),
              ),
              Text(
                'Sincronizado 11:45 AM',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 12,
                  color: CauceColors.creamTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(
                child: _SummaryTile(
                  icon: Icons.warning,
                  iconBg: CauceColors.maroon,
                  value: '2',
                  label: 'Alertas Activas',
                  background: CauceColors.peachErrorContainer,
                  valueColor: Color(0xFF93000A),
                  showPing: true,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _SummaryTile(
                  icon: Icons.receipt_long,
                  iconBg: CauceColors.darkTeal,
                  value: '142',
                  label: 'Eventos hoy',
                  background: CauceColors.peachSecondaryContainer,
                  valueColor: CauceColors.darkTeal,
                  showPing: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.iconBg,
    required this.value,
    required this.label,
    required this.background,
    required this.valueColor,
    required this.showPing,
  });

  final IconData icon;
  final Color iconBg;
  final String value;
  final String label;
  final Color background;
  final Color valueColor;
  final bool showPing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 11,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
          if (showPing)
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: CauceColors.error,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters();

  static const _typeFilters = [
    ('Todos', true),
    ('VR', false),
    ('AR', false),
    ('Tactil', false),
    ('Totem', false),
    ('Proyector', false),
    ('Audio', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.devices,
              size: 18,
              color: CauceColors.creamTertiary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Dispositivo: Todos',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 13,
                  color: CauceColors.peachOnSurfaceVariant,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: CauceColors.peachSurfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Text(
                    'Todos',
                    style: TextStyle(
                      fontFamily: CauceTheme.bodyFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CauceColors.creamPrimary,
                    ),
                  ),
                  Icon(Icons.expand_more, size: 16),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _typeFilters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final (label, selected) = _typeFilters[index];
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? CauceColors.darkTeal
                      : CauceColors.peachSurfaceContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 12,
                    color: selected
                        ? CauceColors.creamSecondaryFixed
                        : CauceColors.peachOnSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.onAction});

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Hoy',
              style: TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: CauceColors.peachOnSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: CauceColors.creamPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '14 eventos recientes',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: CauceColors.creamPrimary,
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Registro de sala',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 12,
                color: CauceColors.creamTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final event in DemoData.activities) ...[
          _EventCard(event: event, onAction: onAction),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onAction});

  final DemoActivity event;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(children: [Container(width: 6, color: event.accent)]),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: event.isAlert
                            ? CauceColors.peachErrorContainer
                            : CauceColors.peachSurfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(event.icon, size: 20, color: event.accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: CauceTheme.displayFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: event.isAlert
                                  ? CauceColors.maroon
                                  : CauceColors.peachOnSurface,
                            ),
                          ),
                          Text(
                            event.subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: CauceTheme.bodyFont,
                              fontSize: 12,
                              color: CauceColors.peachOnSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          event.time,
                          style: TextStyle(
                            fontFamily: CauceTheme.bodyFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: event.accent,
                          ),
                        ),
                        Text(
                          event.relativeTime,
                          style: TextStyle(
                            fontFamily: CauceTheme.bodyFont,
                            fontSize: 10,
                            color: CauceColors.peachOnSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  event.description,
                  style: const TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 13,
                    height: 1.4,
                    color: CauceColors.peachOnSurface,
                  ),
                ),
                if (event.tagLabel != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: CauceColors.peachErrorContainer.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      event.tagLabel!,
                      style: TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: event.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.onAction});

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: onAction,
          style: OutlinedButton.styleFrom(
            backgroundColor: CauceColors.peachSurfaceContainer,
            foregroundColor: CauceColors.peachOnSurface,
            side: BorderSide(
              color: CauceColors.peachOnSurfaceVariant.withValues(alpha: 0.15),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(
            Icons.history,
            size: 20,
            color: CauceColors.creamPrimary,
          ),
          label: const Text(
            'Cargar eventos anteriores (136 restantes)',
            style: TextStyle(fontFamily: CauceTheme.bodyFont, fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Mostrando 6 registros del historial de sala (fase 1: demostracion)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: CauceTheme.bodyFont,
            fontSize: 11,
            color: CauceColors.peachOnSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
