/// Detalle de medio con metadatos reales del servidor.
///
/// La vista previa de imagenes usa el mismo caché de disco que el
/// listado (`ThumbnailService`, clave `id + updated_at`): baja el
/// binario por `GET /api/media/{id}/file` con Authorization, guarda
/// una copia re-escalada a resolucion de vista previa y nunca crece
/// sin limite. Para video y url no hay reproductor en esta fase: se
/// muestran los metadatos reales (el video solo con su metadata
/// completa; el servidor no genera miniaturas de video) y, en los
/// enlaces, la direccion copiable. La eliminacion requiere
/// `content.manage`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/devices_controller.dart';
import '../../controllers/media_library_controller.dart';
import '../../core/capabilities.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../core/utils/date_labels.dart';
import '../../models/assignment.dart';
import '../../models/device.dart';
import '../../models/media.dart';
import '../../services/assignment_service.dart';
import '../../services/thumbnail_service.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/organic_background.dart';

class MediaDetailScreen extends StatefulWidget {
  const MediaDetailScreen({super.key, required this.media});

  /// Medio del inventario recibido desde la biblioteca.
  final Media media;

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  Future<Uint8List?>? _preview;

  @override
  void initState() {
    super.initState();
    if (widget.media.isImage) {
      // Vista previa a resolucion de detalle con el mismo caché de
      // disco del listado (invalidada por updated_at).
      _preview = context.read<MediaLibraryController>().thumbnails.thumbnail(
        widget.media,
        size: ThumbnailSize.detail,
      );
    }
  }

  Future<void> _confirmDelete() async {
    final media = widget.media;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: CauceColors.cream,
        title: const Text('Eliminar medio'),
        content: Text(
          'Se eliminara "${media.name}" del servidor de la sala. Esta '
          'accion no se puede deshacer.',
          style: const TextStyle(
            fontFamily: CauceTheme.bodyFont,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: CauceColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<MediaLibraryController>();
    final ok = await controller.remove(media);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('"${media.name}" eliminado de la biblioteca.'),
          backgroundColor: CauceColors.teal,
        ),
      );
      Navigator.of(context).pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            controller.errorMessage ?? 'El servidor rechazo la eliminacion.',
          ),
          backgroundColor: CauceColors.error,
        ),
      );
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enlace copiado al portapapeles.'),
        backgroundColor: CauceColors.darkTeal,
      ),
    );
  }

  /// Abre el selector de dispositivos para asignar este medio.
  /// Refresco puntual del inventario y las asignaciones al abrir:
  /// garantiza el estado de "ya asignado" y del canal WS.
  Future<void> _openAssignSheet() async {
    final devices = context.read<DevicesController>();
    await devices.refresh();
    if (!mounted) return;
    final service = devices.assignmentService;
    if (service == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CauceColors.cream,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _AssignSheet(
        media: widget.media,
        devices: devices.devices,
        assignments: devices.assignments,
        service: service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final canManage = canManageContent(context);
    return Scaffold(
      backgroundColor: CauceColors.creamSurface,
      body: Stack(
        children: [
          const OrganicBackground(baseColor: CauceColors.creamSurface),
          Column(
            children: [
              StackHeader(
                title: 'Detalle de\nMedio',
                showLogo: false,
                titleFontSize: 16,
                onAvatarTap: () => Navigator.of(context).pushNamed('/profile'),
                backgroundColor: CauceColors.creamSurface,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    32 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PreviewCard(media: media, preview: _preview),
                      const SizedBox(height: 16),
                      _MetadataCard(media: media, onCopyUrl: _copyUrl),
                      if (canManage) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _openAssignSheet,
                          style: FilledButton.styleFrom(
                            backgroundColor: CauceColors.creamPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.devices, size: 18),
                          label: const Text('Asignar a Dispositivos'),
                        ),
                      ],
                      if (canManage) ...[
                        const SizedBox(height: 16),
                        _DangerZone(media: media, onDelete: _confirmDelete),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.media, required this.preview});

  final Media media;
  final Future<Uint8List?>? preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
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
          AspectRatio(
            aspectRatio: 16 / 9,
            child: media.isImage && preview != null
                ? FutureBuilder<Uint8List?>(
                    future: preview,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: CauceColors.creamPrimary,
                          ),
                        );
                      }
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        // Red caida, imagen ilegible o disco sin
                        // espacio: la metadata real sigue visible.
                        return const _PreviewError(
                          message:
                              'No fue posible cargar la vista previa '
                              'desde el servidor.',
                        );
                      }
                      return Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, _, _) =>
                            const _PreviewError(message: 'Imagen ilegible'),
                      );
                    },
                  )
                : _TypePreview(media: media),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    media.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: CauceTheme.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: CauceColors.creamOnSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: CauceColors.creamSecondaryFixed,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    media.typeLabel.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: CauceTheme.bodyFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: CauceColors.creamOnSecondaryFixed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypePreview extends StatelessWidget {
  const _TypePreview({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context) {
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
        // FittedBox: en cajas 16:9 cortas (pantallas pequenas o
        // escala de texto grande) el contenido se encoge en lugar de
        // desbordar por abajo.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  media.typeIcon,
                  size: 48,
                  color: CauceColors.cream.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 8),
                Text(
                  media.isVideo
                      ? 'El servidor no genera miniaturas de video'
                      : 'Enlace externo registrado',
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 12,
                    color: CauceColors.cream.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CauceColors.creamSurfaceContainerHigh,
      child: Center(
        // Mismo FittedBox que _TypePreview: sin overflow en cajas
        // 16:9 cortas.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  size: 40,
                  color: CauceColors.creamSecondary,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: CauceTheme.bodyFont,
                      fontSize: 11,
                      color: CauceColors.creamOnSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.media, required this.onCopyUrl});

  final Media media;
  final ValueChanged<String> onCopyUrl;

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${shortLocalDate(date)} ${two(local.hour)}:'
        '${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Tipo', media.typeLabel),
      if (media.mimeType != null) ('Formato (MIME)', media.mimeType!),
      if (media.readableSize != null) ('Tamano', media.readableSize!),
      ('Creado', _formatDate(media.createdAt)),
      ('Actualizado', _formatDate(media.updatedAt)),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, size: 20, color: CauceColors.creamSecondary),
              SizedBox(width: 6),
              Text(
                'Metadatos',
                style: TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: CauceColors.creamOnSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (label, value) in rows) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: CauceColors.creamOnSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: CauceColors.creamOnSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (media.isUrl && media.externalUrl != null) ...[
            const SizedBox(height: 4),
            const Text(
              'ENLACE REGISTRADO',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: CauceColors.creamOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      media.externalUrl!,
                      style: const TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Copiar enlace',
                    onPressed: () => onCopyUrl(media.externalUrl!),
                    icon: const Icon(
                      Icons.copy,
                      size: 18,
                      color: CauceColors.creamSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.media, required this.onDelete});

  final Media media;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFDAD6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning, size: 20, color: CauceColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Se eliminara "${media.name}" del servidor de la sala. '
                  'Esta accion no se puede deshacer.',
                  style: const TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 13,
                    height: 1.4,
                    color: CauceColors.creamOnSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: CauceColors.error,
              side: const BorderSide(color: CauceColors.error),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            icon: const Icon(Icons.delete_forever, size: 20),
            label: const Text('Eliminar Medio del Circuito de Sala'),
          ),
        ],
      ),
    );
  }
}

/// Selector de dispositivos para asignar un medio a varios equipos.
///
/// Sin endpoint bulk: los PUT viajan en secuencia y el lote nunca se
/// aborta por un fallo individual (marca por fila con el motivo
/// corto). Los dispositivos que ya tienen este medio asignado se
/// muestran "Ya asignado" y no son seleccionables (reasignar el
/// mismo medio solo incrementaria la revision). El estado de
/// sincronizacion sigue siendo del polling: este flujo solo confirma
/// que la asignacion quedo registrada.
class _AssignSheet extends StatefulWidget {
  const _AssignSheet({
    required this.media,
    required this.devices,
    required this.assignments,
    required this.service,
  });

  final Media media;
  final List<Device> devices;
  final List<Assignment> assignments;
  final AssignmentService service;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  /// Uids seleccionados (orden de insercion = orden de ejecucion).
  final Set<String> _selected = {};

  /// Motivo corto de fallo por uid; ausente = asignado.
  final Map<String, String> _errors = {};

  /// Asignados OK pero sin canal de comandos en el momento del PUT
  /// (delivered == false): registrados; cada dispositivo los aplicara
  /// por playback.sync al reconectarse.
  final Set<String> _notDelivered = {};

  bool _running = false;
  int _processed = 0;
  int _ok = 0;

  Assignment? _assignmentOf(String deviceUid) {
    for (final a in widget.assignments) {
      if (a.deviceUid == deviceUid) return a;
    }
    return null;
  }

  Future<void> _run() async {
    if (_running || _selected.isEmpty) return;
    final uids = _selected.toList();
    setState(() {
      _running = true;
      _errors.clear();
      _notDelivered.clear();
      _processed = 0;
      _ok = 0;
    });
    for (final uid in uids) {
      try {
        final assignment = await widget.service.assignMedia(
          uid,
          widget.media.id,
        );
        _ok++;
        if (assignment.delivered == false) {
          _notDelivered.add(uid);
        }
      } on ApiException catch (e) {
        _errors[uid] = e.isAuthError
            ? 'Sin permiso'
            : e.statusCode == 404
            ? 'No encontrado'
            : e.message;
      } catch (_) {
        _errors[uid] = 'Error de red';
      }
      if (mounted) setState(() => _processed = _processed + 1);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final uids = _selected.toList();
    final total = uids.length;
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
            Text(
              'ASIGNAR A DISPOSITIVOS',
              style: const TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CauceColors.maroon,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '"${widget.media.name}". El contenido sincroniza cuando cada '
              'dispositivo lo reporte.',
              style: const TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 12,
                height: 1.4,
                color: CauceColors.creamOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No hay dispositivos registrados en el inventario.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 13,
                    color: CauceColors.creamOnSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.devices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final device = widget.devices[index];
                    final assignment = _assignmentOf(device.deviceUid);
                    final alreadyAssigned =
                        assignment?.mediaId == widget.media.id;
                    final isSelected = _selected.contains(device.deviceUid);
                    final order = uids.indexOf(device.deviceUid);
                    final error = _errors[device.deviceUid];
                    final processedRow =
                        isSelected && order >= 0 && order < _processed;
                    return _DeviceAssignRow(
                      device: device,
                      currentMediaName: assignment?.mediaName,
                      alreadyAssigned: alreadyAssigned,
                      isSelected: isSelected,
                      isCurrent: _running && order == _processed,
                      result: error != null
                          ? _RowResult.error
                          : processedRow
                          ? _RowResult.ok
                          : null,
                      errorReason: error,
                      enabled: !_running && !alreadyAssigned,
                      onToggle: () => setState(() {
                        if (isSelected) {
                          _selected.remove(device.deviceUid);
                        } else {
                          _selected.add(device.deviceUid);
                        }
                      }),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            if (_running)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: total == 0 ? null : _processed / total,
                    color: CauceColors.creamPrimary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Asignando $_processed de $total...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: CauceTheme.bodyFont,
                      fontSize: 12,
                      color: CauceColors.creamOnSurfaceVariant,
                    ),
                  ),
                ],
              )
            else if (_processed > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Asignado a $_ok de $total dispositivos.'
                    '${_notDelivered.isEmpty ? '' : ' ${_notDelivered.length} sin canal de comandos: se aplicaran al reconectarse.'}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: CauceTheme.displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _ok == total
                          ? CauceColors.creamSecondary
                          : CauceColors.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: CauceColors.darkTeal,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Cerrar'),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _selected.isEmpty ? null : _run,
                style: FilledButton.styleFrom(
                  backgroundColor: CauceColors.creamPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.playlist_add_check, size: 18),
                label: Text(
                  _selected.isEmpty
                      ? 'Selecciona dispositivos'
                      : 'Asignar a ${_selected.length} '
                            '${_selected.length == 1 ? 'dispositivo' : 'dispositivos'}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _RowResult { ok, error }

/// Fila de dispositivo del selector: checkbox, nombre, indicador del
/// canal WS y el contenido asignado hoy (cruce con las asignaciones
/// vigentes del servidor).
class _DeviceAssignRow extends StatelessWidget {
  const _DeviceAssignRow({
    required this.device,
    required this.currentMediaName,
    required this.alreadyAssigned,
    required this.isSelected,
    required this.isCurrent,
    required this.enabled,
    required this.onToggle,
    this.result,
    this.errorReason,
  });

  final Device device;
  final String? currentMediaName;

  /// Este medio ya esta asignado al dispositivo: no seleccionable.
  final bool alreadyAssigned;
  final bool isSelected;

  /// Fila que se esta enviando ahora.
  final bool isCurrent;
  final _RowResult? result;
  final String? errorReason;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CauceColors.creamSurfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              result == _RowResult.ok
                  ? const Icon(
                      Icons.check_circle,
                      size: 22,
                      color: CauceColors.success,
                    )
                  : result == _RowResult.error
                  ? const Icon(
                      Icons.error_outline,
                      size: 22,
                      color: CauceColors.error,
                    )
                  : isCurrent
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: CauceColors.creamPrimary,
                      ),
                    )
                  : Checkbox(
                      value: alreadyAssigned ? false : isSelected,
                      onChanged: enabled ? (_) => onToggle() : null,
                    ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            device.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: CauceTheme.displayFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: CauceColors.creamOnSurface,
                            ),
                          ),
                        ),
                        if (alreadyAssigned)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: CauceColors.creamSurfaceContainerHigh,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Ya asignado',
                              style: TextStyle(
                                fontFamily: CauceTheme.bodyFont,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: CauceColors.creamOnSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: device.wsConnected
                                  ? CauceColors.success
                                  : CauceColors.creamOnSurfaceVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      errorReason ??
                          'Contenido actual: ${currentMediaName ?? 'sin asignar'}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: CauceTheme.bodyFont,
                        fontSize: 11,
                        color: errorReason != null
                            ? CauceColors.error
                            : CauceColors.creamOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
