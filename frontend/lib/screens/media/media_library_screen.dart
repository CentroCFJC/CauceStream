/// Biblioteca de medios.
///
/// El listado, los filtros y la busqueda consumen
/// [MediaLibraryController] (GET /api/media). Subir y eliminar
/// requieren `content.manage` y solo se muestran cuando la sesion lo
/// permite; el backend sigue siendo la autoridad (403 como red de
/// seguridad). La distribucion a dispositivos llega en una fase
/// posterior.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../controllers/media_library_controller.dart';
import '../../core/capabilities.dart';
import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../models/media.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/media_type_badge.dart';
import '../../widgets/organic_background.dart';

class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({super.key});

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  final _searchController = TextEditingController();

  /// null = todos; si no, media_type exacto.
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MediaLibraryController>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Media> _filtered(List<Media> media) {
    final query = _searchController.text.trim().toLowerCase();
    return media
        .where(
          (m) =>
              (_typeFilter == null || m.mediaType == _typeFilter) &&
              (query.isEmpty ||
                  m.name.toLowerCase().contains(query) ||
                  (m.mimeType ?? '').toLowerCase().contains(query)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = canManageContent(context);
    return Stack(
      children: [
        const ColoredBox(color: CauceColors.peachSurface),
        const OrganicBackground(
          topRight: true,
          bottomLeft: true,
          baseColor: CauceColors.peachSurface,
        ),
        Column(
          children: [
            TabHeader(
              title: 'Biblioteca',
              onAvatarTap: () =>
                  Navigator.of(context).pushNamed(Routes.profile),
            ),
            Expanded(
              child: Consumer<MediaLibraryController>(
                builder: (context, controller, _) {
                  return Stack(
                    children: [
                      RefreshIndicator(
                        color: CauceColors.peachPrimary,
                        onRefresh: () => controller.refresh(),
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 140),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LibrarySearch(
                                controller: _searchController,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 12),
                              _FilterChips(
                                media: controller.media,
                                selected: _typeFilter,
                                onSelect: (type) =>
                                    setState(() => _typeFilter = type),
                              ),
                              const SizedBox(height: 16),
                              ..._buildBody(context, controller),
                            ],
                          ),
                        ),
                      ),
                      if (canManage)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton.extended(
                            onPressed: () => Navigator.of(
                              context,
                            ).pushNamed(Routes.mediaRegister),
                            backgroundColor: CauceColors.peachPrimaryContainer,
                            foregroundColor: Colors.white,
                            icon: const Icon(Icons.add_circle, size: 22),
                            label: const Text(
                              'Nuevo Medio',
                              style: TextStyle(
                                fontFamily: CauceTheme.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    MediaLibraryController controller,
  ) {
    if (controller.status == MediaLibraryStatus.loading &&
        controller.media.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: CircularProgressIndicator(color: CauceColors.peachPrimary),
          ),
        ),
      ];
    }
    if (controller.status == MediaLibraryStatus.error &&
        controller.media.isEmpty) {
      return [
        _NoticeCard(
          icon: Icons.wifi_off,
          message:
              controller.errorMessage ??
              'No fue posible consultar la biblioteca.',
          actionLabel: 'Reintentar',
          onAction: () => controller.refresh(),
        ),
      ];
    }
    final media = controller.media;
    if (media.isEmpty) {
      return const [
        _NoticeCard(
          icon: Icons.video_library_outlined,
          message:
              'La biblioteca esta vacia. Sube una imagen o video, o registra '
              'un enlace para comenzar.',
        ),
      ];
    }
    final filtered = _filtered(media);
    if (filtered.isEmpty) {
      return const [
        _NoticeCard(
          icon: Icons.search_off,
          message: 'Ningun medio coincide con la busqueda.',
        ),
      ];
    }
    return [
      // Dos tarjetas por fila: cada una ocupa el 50% del ancho.
      LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in filtered)
                SizedBox(
                  width: cardWidth,
                  // Clave por id + updated_at: al recargar con un
                  // medio nuevo arriba, cada tarjeta conserva su
                  // propio estado (y su miniatura) en lugar de heredar
                  // el de otra posicion.
                  child: MediaCard(
                    key: ValueKey(
                      'media_${item.id}_${item.updatedAt.millisecondsSinceEpoch}',
                    ),
                    media: item,
                  ),
                ),
            ],
          );
        },
      ),
      if (controller.hasMore) ...[
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => controller.loadMore(),
          style: OutlinedButton.styleFrom(
            foregroundColor: CauceColors.peachPrimary,
            side: BorderSide(color: CauceColors.peachPrimaryContainer),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: const Icon(Icons.expand_more, size: 20),
          label: const Text(
            'Cargar mas',
            style: TextStyle(
              fontFamily: CauceTheme.displayFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
      if (controller.errorMessage != null && media.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          controller.errorMessage!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: CauceTheme.bodyFont,
            fontSize: 11,
            color: CauceColors.peachOnSurfaceVariant,
          ),
        ),
      ],
    ];
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: CauceColors.peachSecondary),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
              height: 1.4,
              color: CauceColors.peachOnSurfaceVariant,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: CauceColors.peachPrimaryContainer,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibrarySearch extends StatelessWidget {
  const _LibrarySearch({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: CauceColors.peachSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o formato...',
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(fontFamily: CauceTheme.bodyFont, fontSize: 15),
            ),
          ),
          Icon(Icons.tune, size: 20, color: CauceColors.peachSecondary),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.media,
    required this.selected,
    required this.onSelect,
  });

  final List<Media> media;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    int count(String? type) => type == null
        ? media.length
        : media.where((m) => m.mediaType == type).length;
    final filters = <(String?, String)>[
      (null, 'Todos (${count(null)})'),
      ('image', 'Imagenes (${count('image')})'),
      ('video', 'Videos (${count('video')})'),
      ('url', 'Enlaces (${count('url')})'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (type, label) = filters[index];
          final isSelected = type == selected;
          return GestureDetector(
            onTap: () => onSelect(type),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 18 : 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? CauceColors.peachPrimary
                    : CauceColors.peachSurfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : CauceColors.peachOnSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Tarjeta de medio (ocupa el 50% del ancho: dos por fila): miniatura
/// real de las imagenes (caché de disco, via `GET /api/media/{id}/file`)
/// o lienzo de tipo para video/url, con la insignia del tipo solo con
/// icono sobre la previsualizacion, y el nombre debajo. Sin peso, sin
/// fecha y sin accion de envio.
class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.media});

  final Media media;

  Color get _accent => switch (media.mediaType) {
    'image' => CauceColors.teal,
    'video' => CauceColors.darkTeal,
    _ => CauceColors.maroon,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(
          context,
        ).pushNamed(Routes.mediaDetail, arguments: media),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 104,
                  child: _CardPreview(media: media, accent: _accent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                media.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: const TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: CauceColors.peachOnSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Previsualizacion de la tarjeta. Imagenes: miniatura real desde el
/// caché (`ThumbnailService`); video y url: lienzo con el icono de
/// tipo (el backend no genera miniaturas de video). El dato nunca
/// queda tapado por el adorno.
class _CardPreview extends StatefulWidget {
  const _CardPreview({required this.media, required this.accent});

  final Media media;
  final Color accent;

  @override
  State<_CardPreview> createState() => _CardPreviewState();
}

class _CardPreviewState extends State<_CardPreview> {
  Future<Uint8List?>? _thumbnail;

  @override
  void initState() {
    super.initState();
    if (widget.media.isImage) {
      // Solo imagenes: video y url no tienen binario para mostrar.
      _thumbnail = context.read<MediaLibraryController>().thumbnails.thumbnail(
        widget.media,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _CardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defensa extra por si el widget se reusa con otro medio (sin
    // clave): la miniatura siempre corresponde al medio actual.
    if (widget.media.id != oldWidget.media.id ||
        widget.media.updatedAt != oldWidget.media.updatedAt) {
      _thumbnail = widget.media.isImage
          ? context.read<MediaLibraryController>().thumbnails.thumbnail(
              widget.media,
            )
          : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final future = _thumbnail;
    if (media.isImage && future != null) {
      return FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final bytes = snapshot.data;
            if (bytes != null) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Ya viene re-escalada por el caché: es una
                  // miniatura, no el archivo original.
                  Positioned.fill(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => _TypeCanvas(
                        media: media,
                        accent: widget.accent,
                        label: 'Imagen ilegible',
                        broken: true,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: MediaTypeBadge(media: media, iconOnly: true),
                  ),
                ],
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                _TypeCanvas(
                  media: media,
                  accent: widget.accent,
                  label: 'Vista previa no disponible',
                  broken: true,
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: MediaTypeBadge(media: media, iconOnly: true),
                ),
              ],
            );
          }
          return _TypeCanvas(
            media: media,
            accent: widget.accent,
            loading: true,
          );
        },
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _TypeCanvas(
          media: media,
          accent: widget.accent,
          label: media.isVideo ? 'Miniatura no disponible' : null,
        ),
        Positioned(
          top: 8,
          left: 8,
          child: MediaTypeBadge(media: media, iconOnly: true),
        ),
      ],
    );
  }
}

/// Lienzo de tipo (video / url / cargando). Conserva el acento del
/// tema Cauce sin competir con la data de la tarjeta.
class _TypeCanvas extends StatelessWidget {
  const _TypeCanvas({
    required this.media,
    required this.accent,
    this.label,
    this.loading = false,
    this.broken = false,
  });

  final Media media;
  final Color accent;
  final String? label;
  final bool loading;
  final bool broken;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CauceColors.peachSurfaceContainerHigh,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.22),
                    accent.withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  broken ? Icons.broken_image_outlined : media.typeIcon,
                  size: 38,
                  color: accent.withValues(alpha: 0.85),
                ),
                if (label != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      label!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 11,
                        color: CauceColors.peachOnSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (loading)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: CauceColors.peachPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
