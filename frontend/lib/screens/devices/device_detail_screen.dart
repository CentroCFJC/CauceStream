/// Detalle de dispositivo.
///
/// Los datos de la pastilla de conectividad y la tarjeta de
/// informacion provienen del inventario real ([Device]), refrescado
/// por el sondeo del inventario. La tarjeta de contenido muestra la asignacion vigente
/// (una por dispositivo) con su estado de sincronizacion, que solo
/// mueve el servidor via heartbeat: la UI nunca lo computa. Las
/// acciones remotas de energia viajan por el canal WebSocket del
/// dispositivo. No hay contrato de control de reproduccion: esa
/// ronda no incluye controles de reproduccion.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/devices_controller.dart';
import '../../controllers/media_library_controller.dart';
import '../../core/capabilities.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../models/assignment.dart';
import '../../models/device.dart';
import '../../models/media.dart';
import '../../services/thumbnail_service.dart';
import 'device_register_screen.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/device_connection_status.dart';
import '../../widgets/media_type_badge.dart';
import '../../widgets/organic_background.dart';
import '../../widgets/stale_data_notice.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.device});

  /// Dispositivo del inventario recibido desde la lista.
  final Device device;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  /// Ultima asignacion creada desde esta vista (respuesta del PUT):
  /// manda mientras el sondeo no traiga una revision igual o mayor.
  /// Muestra lo que respondio el backend (normalmente `pending`);
  /// nunca la marca como sincronizada a mano.
  Assignment? _localAssignment;

  @override
  void initState() {
    super.initState();
    // Diferido al primer frame: ensureLoaded notifica (cambia a
    // loading) y no puede hacerse durante el build inicial.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MediaLibraryController>().ensureLoaded();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DevicesController>(
      builder: (context, controller, _) {
        final current = _latestFrom(controller);
        final assignment = _resolveAssignment(controller);
        return Consumer<MediaLibraryController>(
          builder: (context, library, _) {
            final media = _mediaFor(assignment, library);
            return Scaffold(
              backgroundColor: CauceColors.peachSurface,
              body: Stack(
                children: [
                  const OrganicBackground(
                    topRight: true,
                    bottomLeft: true,
                    baseColor: CauceColors.peachSurface,
                  ),
                  Column(
                    children: [
                      StackHeader(
                        title: 'Detalle de\nDispositivo',
                        showLogo: false,
                        titleFontSize: 16,
                        onAvatarTap: () =>
                            Navigator.of(context).pushNamed('/profile'),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            16,
                            24,
                            32 + MediaQuery.paddingOf(context).bottom,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (controller.isStale) ...[
                                StaleDataNotice(
                                  fetchedAt: controller.fetchedAt,
                                ),
                                const SizedBox(height: 12),
                              ],
                              // Pastilla del dispositivo (icono de
                              // tipo + nombre + estado) y conector
                              // hacia la pastilla del servidor del
                              // encabezado.
                              DeviceConnectionStatus(
                                device: current,
                                stale: controller.isStale,
                              ),
                              const SizedBox(height: 16),
                              _AssignedContentCard(
                                assignment: assignment,
                                media: media,
                                canManage: canManageContent(context),
                                onChangeContent: _openMediaPicker,
                              ),
                              const SizedBox(height: 16),
                              _ActionButtons(device: current),
                              const SizedBox(height: 16),
                              // Panel de informacion: desplegable
                              // plegado por defecto, debajo de las
                              // acciones (es lo menos relevante).
                              _TelemetryCard(device: current),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Version mas reciente del dispositivo segun el sondeo del
  /// inventario (mismo ciclo que alimenta la lista). Si el polling
  /// no lo trae, se conserva el snapshot recibido por argumento.
  Device _latestFrom(DevicesController controller) {
    for (final d in controller.devices) {
      if (d.id == widget.device.id) return d;
    }
    return widget.device;
  }

  /// Asignacion vigente segun el sondeo, salvo que exista una
  /// asignacion local mas reciente (revision mayor) creada en esta
  /// vista y todavia no reflejada por el polling.
  Assignment? _resolveAssignment(DevicesController controller) {
    final polled = controller.assignmentOf(widget.device.deviceUid);
    final local = _localAssignment;
    if (local == null) return polled;
    if (polled == null || polled.revision < local.revision) return local;
    return polled;
  }

  /// Medio de la biblioteca que corresponde a la asignacion (para
  /// icono de tipo y miniatura); null si la biblioteca no lo trae.
  Media? _mediaFor(Assignment? assignment, MediaLibraryController library) {
    final id = assignment?.mediaId;
    if (id == null) return null;
    for (final m in library.media) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _openMediaPicker() async {
    final library = context.read<MediaLibraryController>();
    // Si la biblioteca aun carga (primera apertura), se espera aqui;
    // si ya esta lista, no hay peticion nueva.
    await library.ensureLoaded();
    if (!mounted) return;
    final currentId =
        _localAssignment?.mediaId ??
        context
            .read<DevicesController>()
            .assignmentOf(widget.device.deviceUid)
            ?.mediaId;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CauceColors.cream,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _MediaPickerSheet(
        media: library.media,
        currentMediaId: currentId,
        thumbnails: library.thumbnails,
        onSelected: (selected) {
          Navigator.of(sheetContext).pop();
          _assign(selected);
        },
      ),
    );
  }

  Future<void> _assign(Media media) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<DevicesController>().assignmentService;
    if (service == null) return;
    try {
      final assignment = await service.assignMedia(
        widget.device.deviceUid,
        media.id,
      );
      if (!mounted) return;
      // Muestra exactamente lo que respondio el backend (normalmente
      // pending); el paso a sincronizado lo trae el polling.
      setState(() => _localAssignment = assignment);
      // delivered = se escribio al canal vivo sin error. Sin canal,
      // la asignacion persistida le llega al TV por playback.sync en
      // su proxima conexion (verificado por el backend en
      // test_sync_contains_persisted_assignment).
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            assignment.delivered == false
                ? '"${media.name}" registrado. El TV no tiene canal de '
                      'comandos ahora: lo tomara al reconectarse.'
                : '"${media.name}" asignado. Sincroniza cuando el '
                      'dispositivo lo reporte.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (e.isAuthError) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No tienes permiso para asignar contenido.'),
          ),
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo asignar el contenido.')),
      );
    }
  }
}

class _AssignedContentCard extends StatelessWidget {
  const _AssignedContentCard({
    required this.assignment,
    required this.media,
    required this.canManage,
    required this.onChangeContent,
  });

  final Assignment? assignment;

  /// Medio de la biblioteca correspondiente (icono de tipo y
  /// miniatura); null si la biblioteca no lo trae: queda el nombre
  /// que reporta la asignacion.
  final Media? media;

  /// `content.manage`: sin el, el boton queda atenuado y avisa al
  /// pulsar (nunca muerto); el 403 del servidor es la red de
  /// seguridad.
  final bool canManage;
  final VoidCallback onChangeContent;

  @override
  Widget build(BuildContext context) {
    final thumbnails = context.read<MediaLibraryController>().thumbnails;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CauceColors.cream,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'REPRODUCIENDO AHORA',
                  style: TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                    color: CauceColors.peachSecondary,
                  ),
                ),
              ),
              _SyncIndicator(assignment: assignment),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            assignment?.mediaName ?? 'Sin contenido asignado',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: CauceTheme.displayFont,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: CauceColors.darkTeal,
            ),
          ),
          const SizedBox(height: 16),
          _MediaPreview(
            media: media,
            assigned: assignment != null,
            thumbnails: thumbnails,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onChangeContent,
            style: FilledButton.styleFrom(
              backgroundColor: canManage
                  ? CauceColors.creamPrimary
                  : CauceColors.peachSecondary.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.playlist_play, size: 18),
            label: const Text(
              'Cambiar Contenido',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado de sincronizacion segun el servidor: chulito verde cuando
/// el contenido esta sincronizado, circulo de carga mientras
/// sincroniza. Sin asignacion no se dibuja nada.
class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.assignment});

  final Assignment? assignment;

  @override
  Widget build(BuildContext context) {
    if (assignment == null) return const SizedBox.shrink();
    final synced = assignment!.isSynchronized;
    return Semantics(
      label: synced
          ? 'Contenido sincronizado con el dispositivo'
          : 'Sincronizando contenido con el dispositivo',
      child: synced
          ? const Icon(Icons.check_circle, size: 20, color: CauceColors.success)
          : const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: CauceColors.alert,
              ),
            ),
    );
  }
}

/// Vista previa del medio asignado: miniatura para imagenes (mismo
/// cache de disco de la biblioteca), lienzo de tipo para video/url y
/// aviso claro cuando no hay asignacion.
class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.media,
    required this.assigned,
    required this.thumbnails,
  });

  final Media? media;
  final bool assigned;
  final ThumbnailService thumbnails;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (!assigned) {
      content = _TypeCanvas(
        media: null,
        hint: 'Este dispositivo no tiene contenido asignado',
      );
    } else if (media != null && media!.isImage) {
      content = _MediaThumbnail(media: media!, thumbnails: thumbnails);
    } else {
      content = _TypeCanvas(media: media);
    }
    // Pastilla de tipo sobre la miniatura, igual que en la vista de
    // Medios (Positioned top/left). Sin StackFit.expand: la altura la
    // fija la propia vista previa (el Stack vive en una columna con
    // altura sin limitar).
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(height: 128, width: double.infinity, child: content),
          if (media != null)
            Positioned(top: 8, left: 8, child: MediaTypeBadge(media: media!)),
        ],
      ),
    );
  }
}

/// Lienzo de degradado con el icono de tipo del medio (o el aviso
/// correspondiente cuando falta el dato).
class _TypeCanvas extends StatelessWidget {
  const _TypeCanvas({required this.media, this.hint});

  final Media? media;

  /// Texto alternativo cuando no hay medio que mostrar.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    // Sin etiqueta de tipo: la pastilla de la cabecera ya lo muestra.
    final label = hint ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(CauceColors.darkTeal, CauceColors.orange, 0.35)!,
            CauceColors.darkTeal,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              media?.typeIcon ?? Icons.tv,
              size: 34,
              color: CauceColors.cream.withValues(alpha: 0.9),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 12,
                    color: CauceColors.cream.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Miniatura estable de un medio de la biblioteca: el Future se
/// resuelve una vez por medio (id + updated_at) para no reencolar
/// descargas en cada rebuild del sondeo.
class _MediaThumbnail extends StatefulWidget {
  const _MediaThumbnail({required this.media, required this.thumbnails});

  final Media media;
  final ThumbnailService thumbnails;

  @override
  State<_MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<_MediaThumbnail> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.thumbnails.thumbnail(
      widget.media,
      size: ThumbnailSize.card,
    );
  }

  @override
  void didUpdateWidget(covariant _MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.media.updatedAt != widget.media.updatedAt) {
      _future = widget.thumbnails.thumbnail(
        widget.media,
        size: ThumbnailSize.card,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => _TypeCanvas(media: widget.media),
          );
        }
        return _TypeCanvas(media: widget.media);
      },
    );
  }
}

/// Selector de medios de la biblioteca para reemplazar la asignacion
/// del dispositivo: filtrable por tipo, con el medio vigente marcado
/// como "Actual" y confirmacion explicita antes del PUT.
class _MediaPickerSheet extends StatefulWidget {
  const _MediaPickerSheet({
    required this.media,
    required this.currentMediaId,
    required this.thumbnails,
    required this.onSelected,
  });

  final List<Media> media;
  final int? currentMediaId;
  final ThumbnailService thumbnails;
  final ValueChanged<Media> onSelected;

  @override
  State<_MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<_MediaPickerSheet> {
  static const List<(String, String)> _filters = [
    ('all', 'Todos'),
    ('image', 'Imagen'),
    ('video', 'Video'),
    ('url', 'Enlace'),
  ];

  String _filter = 'all';
  Media? _selected;

  @override
  Widget build(BuildContext context) {
    final items = widget.media
        .where((m) => _filter == 'all' || m.mediaType == _filter)
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CAMBIAR CONTENIDO',
              style: TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CauceColors.maroon,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Elige el medio que reproducira este dispositivo. La '
              'sincronizacion llega cuando el dispositivo lo reporte.',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 12,
                height: 1.4,
                color: CauceColors.peachOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final (value, label) in _filters)
                  _filterChip(value, label, _filter == value),
              ],
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No hay medios en la biblioteca con este filtro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 13,
                    color: CauceColors.peachOnSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final m = items[index];
                    final isSelected = _selected?.id == m.id;
                    return _MediaRow(
                      media: m,
                      thumbnails: widget.thumbnails,
                      isCurrent: m.id == widget.currentMediaId,
                      isSelected: isSelected,
                      onTap: () =>
                          setState(() => _selected = isSelected ? null : m),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _selected == null
                  ? null
                  : () => widget.onSelected(_selected!),
              style: FilledButton.styleFrom(
                backgroundColor: CauceColors.creamPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.playlist_add_check, size: 18),
              label: Text(
                _selected == null
                    ? 'Selecciona un medio'
                    : 'Asignar "${_selected!.name}"',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label, bool active) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: active
              ? CauceColors.creamPrimary
              : CauceColors.peachSurfaceContainer.withValues(alpha: 0.5),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _filter = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? CauceColors.cream : CauceColors.darkTeal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de medio del selector: miniatura, nombre, tipo y marca de
/// "Actual" para el medio vigente (no seleccionable: reasignar el
/// mismo medio solo incrementaria la revision).
class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.media,
    required this.thumbnails,
    required this.isCurrent,
    required this.isSelected,
    required this.onTap,
  });

  final Media media;
  final ThumbnailService thumbnails;
  final bool isCurrent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? CauceColors.peachSurfaceContainer
          : CauceColors.peachSurfaceContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isCurrent ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: media.isImage
                      ? _MediaThumbnail(media: media, thumbnails: thumbnails)
                      : _TypeCanvas(media: media),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: CauceTheme.displayFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CauceColors.darkTeal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      media.typeLabel,
                      style: const TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 11,
                        color: CauceColors.peachSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: CauceColors.peachSurfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Actual',
                    style: TextStyle(
                      fontFamily: CauceTheme.displayFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: CauceColors.darkTeal,
                    ),
                  ),
                )
              else
                Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected
                      ? CauceColors.success
                      : CauceColors.peachSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel de informacion del dispositivo (IP, identificador, tipo,
/// MAC, puerto, ultima conexion): desplegable PLEGADO por defecto y
/// ubicado debajo de las acciones, porque es lo menos relevante de la
/// vista. El boton de edicion vive en la cabecera, fuera del cuerpo
/// plegable.
class _TelemetryCard extends StatefulWidget {
  const _TelemetryCard({required this.device});

  final Device device;

  @override
  State<_TelemetryCard> createState() => _TelemetryCardState();
}

class _TelemetryCardState extends State<_TelemetryCard> {
  /// Nace plegado: la informacion es secundaria en esta pantalla.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final stats = [
      ('Direccion IP', device.ipAddress ?? 'No reportada'),
      ('Identificador', device.deviceUid),
      ('Tipo', device.type),
      ('MAC (Wake-on-LAN)', device.macAddress ?? 'No reportada'),
      ('Puerto', device.port?.toString() ?? 'Sin definir'),
      ('Ultima conexion', device.relativeLastSeen ?? 'Sin latidos'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: CauceColors.cream,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
                child: Row(
                  children: [
                    Icon(Icons.memory, size: 18, color: CauceColors.teal),
                    const SizedBox(width: 8),
                    const Text(
                      'INFORMACION',
                      style: TextStyle(
                        fontFamily: CauceTheme.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: CauceColors.darkTeal,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Editar tipo y MAC',
                      icon: const Icon(Icons.edit, size: 18),
                      color: CauceColors.teal,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => _EditDeviceDialog(device: device),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.expand_more,
                        size: 22,
                        color: CauceColors.peachOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Al plegar, el contenido se desmonta (no queda montado con
          // altura 0): AnimatedSize anima la altura del cambio.
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Dos celdas por fila con altura propia
                          // (intrinsic): sin relacion de aspecto fija, asi
                          // ninguna celda desborda con escala de texto
                          // grande o etiquetas que se envuelven.
                          for (var i = 0; i < stats.length; i += 2) ...[
                            if (i > 0) const SizedBox(height: 10),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _StatCell(
                                      label: stats[i].$1,
                                      value: stats[i].$2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: i + 1 < stats.length
                                        ? _StatCell(
                                            label: stats[i + 1].$1,
                                            value: stats[i + 1].$2,
                                          )
                                        : const SizedBox(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

/// Celda de dato del inventario (Direccion IP, Identificador,
/// Puerto, Ultima conexion): etiqueta + valor con altura propia.
class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CauceColors.peachSurfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: CauceColors.peachSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: CauceTheme.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: CauceColors.darkTeal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Acciones remotas de energia (POST /api/devices/{uid}/power).
/// Encender = salir de espera; Apagar = entrar en espera (el equipo
/// sigue latiendo).
///
/// El servidor ejecuta el comando con el controlador del `type` del
/// dispositivo (p. ej. ADB desde el servidor para google_tv/android_tv,
/// usando la IP del ultimo heartbeat; sin canal WebSocket no importa).
/// Los pills nunca quedan muertos: durante el envio se bloquean para
/// evitar doble tap y el resultado (`method`/`detail`) se muestra en el
/// snackbar. No se altera optimistamente el estado mostrado: el estado
/// real lo trae el polling del heartbeat.
class _ActionButtons extends StatefulWidget {
  const _ActionButtons({required this.device});

  final Device device;

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _sending = false;

  void _handleTap(String action) {
    if (_sending) return;
    _confirm(action);
  }

  Future<void> _send(String action) async {
    if (_sending) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<DevicesController>().service;
    setState(() => _sending = true);
    try {
      final result = await service.sendPowerCommand(
        widget.device.deviceUid,
        action,
      );
      final verbo = action == 'on' ? 'Encender' : 'Apagar';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? '$verbo: ${result.detail.isEmpty ? 'comando ejecutado por ${result.method}' : result.detail}'
                : '$verbo falló (${result.method}): ${result.detail}',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_messageFor(e))));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo enviar el comando al servidor.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _messageFor(ApiException e) {
    if (e.statusCode == 409) {
      return 'Este tipo de dispositivo usa el canal WebSocket y no tiene canal en vivo; conectalo primero.';
    }
    if (e.statusCode == 504) {
      return 'El comando tardo demasiado; revisa que el dispositivo este en la red.';
    }
    if (e.isAuthError) {
      return 'No tienes permiso para controlar este dispositivo.';
    }
    return e.message;
  }

  void _confirm(String action) {
    final isOn = action == 'on';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CauceColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: CauceColors.peachSurfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOn ? Icons.power_settings_new : Icons.bedtime,
                size: 28,
                color: isOn ? CauceColors.success : CauceColors.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isOn ? 'ENCENDER PANTALLA' : 'APAGAR PANTALLA',
              style: const TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CauceColors.maroon,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isOn
                  ? 'La pantalla saldra del modo espera.'
                  : 'La pantalla entrara en modo espera; el dispositivo sigue conectado y enviando latidos.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 13,
                height: 1.4,
                color: CauceColors.peachOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _send(action);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: isOn
                      ? CauceColors.success
                      : CauceColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: Text(isOn ? 'Encender' : 'Apagar'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.device.wsConnected && !_sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ACCIONES',
          style: TextStyle(
            fontFamily: CauceTheme.displayFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: CauceColors.peachSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionPill(
                icon: Icons.power_settings_new,
                label: 'Encender',
                color: CauceColors.success,
                enabled: enabled,
                onTap: () => _handleTap('on'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionPill(
                icon: Icons.bedtime,
                label: 'Apagar',
                color: CauceColors.error,
                enabled: enabled,
                onTap: () => _handleTap('off'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// false = sin canal WS o envio en curso: pill atenuado. El tap
  /// sigue respondiendo con un aviso; nunca queda muerto.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? color : color.withValues(alpha: 0.35);
    return Material(
      color: enabled
          ? CauceColors.peachSurfaceContainer
          : CauceColors.peachSurfaceContainer.withValues(alpha: 0.5),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diálogo para editar el `type` y la MAC de un dispositivo registrado.
///
/// El `type` no es cosmético: selecciona el controlador de energia que
/// usa el servidor en POST /api/devices/{uid}/power (google_tv/android_tv
/// -> ADB desde el servidor usando la IP del heartbeat; otro tipo ->
/// canal WebSocket del cliente). La MAC alimenta el Wake-on-LAN.
class _EditDeviceDialog extends StatefulWidget {
  const _EditDeviceDialog({required this.device});

  final Device device;

  @override
  State<_EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<_EditDeviceDialog> {
  late String _type;
  late final TextEditingController _macController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.device.type;
    _macController = TextEditingController(
      text: widget.device.macAddress ?? '',
    );
  }

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = context.read<DevicesController>().service;
      await service.updateDevice(
        widget.device.deviceUid,
        type: _type,
        macAddress: _macController.text.trim(),
      );
      if (!mounted) return;
      unawaited(context.read<DevicesController>().refresh());
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CauceColors.cream,
      title: const Text(
        'Editar dispositivo',
        style: TextStyle(
          fontFamily: CauceTheme.displayFont,
          color: CauceColors.maroon,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: [
              // Si el dispositivo tiene un type legacy fuera de la lista
              // canonica, se muestra como item extra para no romper el dropdown.
              if (!DeviceRegisterScreen.stationOptions.any(
                (o) => o.$3 == _type,
              ))
                DropdownMenuItem(value: _type, child: Text('$_type (legacy)')),
              for (final option in DeviceRegisterScreen.stationOptions)
                DropdownMenuItem(value: option.$3, child: Text(option.$2)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _macController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'MAC (Wake-on-LAN, opcional)',
              hintText: '7C:01:3E:7A:7D:52',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: CauceColors.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
