/// Registro de medio: archivo local (multipart) o URL externa.
///
/// Subir/eliminar requiere `content.manage`; el boton de guardado
/// envia el contrato real del backend (POST /api/media o
/// POST /api/media/urls) y muestra los errores del servidor (413 =
/// tamano, 400 = extension/MIME, 403 = permisos) conservando los
/// datos del formulario.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/media_library_controller.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../models/media.dart';
import '../../services/media_service.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/organic_background.dart';

class MediaRegisterScreen extends StatefulWidget {
  const MediaRegisterScreen({super.key});

  @override
  State<MediaRegisterScreen> createState() => _MediaRegisterScreenState();
}

class _MediaRegisterScreenState extends State<MediaRegisterScreen> {
  static const _allowedExtensions = MediaService.allowedExtensions;

  int _sourceTab = 0; // 0 = archivo local, 1 = URL externa

  Uint8List? _fileBytes;
  String _fileName = '';
  int _fileSize = 0;

  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _mimeController = TextEditingController();

  bool _saving = false;

  /// Progreso de subida [0..1]; null cuando no hay envio en curso.
  double? _uploadProgress;
  String? _error;

  String? get _fileType => MediaService.mediaTypeForExtension(_fileName);

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _mimeController.dispose();
    super.dispose();
  }

  MediaService get _service => context.read<MediaLibraryController>().service;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() {
      _fileBytes = file.bytes;
      _fileName = file.name;
      _fileSize = file.size;
      // Nombre sugerido vacio: el servidor conserva el original.
      if (_nameController.text.isEmpty) {
        _nameController.text = file.name;
      }
      _error = null;
    });
  }

  /// Mensaje de error especifico para cada fallo clasificado por
  /// [ApiException]. El `detail` del backend se conserva cuando
  /// aporta.
  String _errorMessageFor(ApiException e) {
    if (e.statusCode == 403) {
      return 'Tu rol no tiene permiso para gestionar el contenido de la '
          'sala (content.manage).';
    }
    if (e.statusCode == 404) {
      return 'El recurso no existe en el servidor (404).';
    }
    if (e.statusCode == 413) {
      return 'El archivo es demasiado grande para el servidor: ${e.message}';
    }
    if (e.statusCode == 400 || e.statusCode == 422) {
      return 'El servidor rechazo el archivo (tipo o extension no valida): '
          '${e.message}';
    }
    if (e.kind == ApiErrorKind.network) {
      return 'Se perdio la conexion con el servidor durante el envio. '
          'Verifica la red de la sala e intenta de nuevo.';
    }
    return e.message;
  }

  Future<void> _onSave() async {
    if (_saving) return;
    final name = _nameController.text.trim();

    if (_sourceTab == 0) {
      // Validacion previa al envio: nada gasta la LAN si el backend
      // iba a rechazarlo igual (extension o tamano).
      final validation = MediaService.validateUploadFile(
        _fileName,
        _fileBytes?.length ?? _fileSize,
      );
      if (validation != null) {
        setState(() => _error = validation);
        return;
      }
    } else {
      if (name.isEmpty) {
        setState(() => _error = 'Escribe un nombre para el enlace.');
        return;
      }
      final url = _urlController.text.trim();
      final parsed = Uri.tryParse(url);
      if (url.isEmpty ||
          parsed == null ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        setState(
          () => _error =
              'La URL debe ser valida y comenzar por http:// o https://.',
        );
        return;
      }
    }

    setState(() {
      _saving = true;
      _uploadProgress = null;
      _error = null;
    });
    try {
      final Media created;
      if (_sourceTab == 0) {
        created = await _service.uploadFile(
          bytes: _fileBytes!,
          filename: _fileName,
          mediaType: _fileType!,
          name: name.isEmpty ? null : name,
          onProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            setState(() => _uploadProgress = sent / total);
          },
        );
      } else {
        created = await _service.registerUrl(
          name: name,
          url: _urlController.text.trim(),
          mimeType: _mimeController.text.trim(),
        );
      }
      if (!mounted) return;
      // Recarga del servidor: nunca optimista.
      unawaited(context.read<MediaLibraryController>().refresh());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${created.name}" guardado en la biblioteca.'),
          backgroundColor: CauceColors.teal,
        ),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _uploadProgress = null;
        _error = _errorMessageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CauceColors.creamSurface,
      body: Stack(
        children: [
          const OrganicBackground(baseColor: CauceColors.creamSurface),
          Column(
            children: [
              const StackHeader(
                title: 'Nuevo\nMedio',
                closeInsteadOfBack: true,
                showLogo: false,
                titleFontSize: 16,
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
                      _SourceTabs(
                        tab: _sourceTab,
                        onChanged: (t) => setState(() {
                          _sourceTab = t;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      if (_sourceTab == 0)
                        _FilePanel(
                          bytes: _fileBytes,
                          fileName: _fileName,
                          fileSize: _fileSize,
                          mediaType: _fileType,
                          nameController: _nameController,
                          onPick: _pickFile,
                        )
                      else
                        _UrlPanel(
                          nameController: _nameController,
                          urlController: _urlController,
                          mimeController: _mimeController,
                        ),
                      const SizedBox(height: 16),
                      if (_saving) ...[
                        if (_sourceTab == 0 && _uploadProgress != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Subiendo a la sala...',
                                style: const TextStyle(
                                  fontFamily: CauceTheme.bodyFont,
                                  fontSize: 12,
                                  color: CauceColors.creamOnSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${(_uploadProgress! * 100).round()}%',
                                style: const TextStyle(
                                  fontFamily: CauceTheme.bodyFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: CauceColors.creamOnSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            minHeight: 6,
                            value: _uploadProgress,
                            backgroundColor:
                                CauceColors.creamSurfaceContainerHigh,
                            color: CauceColors.creamPrimary,
                          ),
                        ] else ...[
                          const LinearProgressIndicator(
                            minHeight: 6,
                            backgroundColor:
                                CauceColors.creamSurfaceContainerHigh,
                            color: CauceColors.creamPrimary,
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                      FilledButton.icon(
                        onPressed: _saving ? null : _onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: CauceColors.creamPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          _sourceTab == 0 ? Icons.cloud_upload : Icons.link,
                          size: 20,
                        ),
                        label: Text(
                          _saving
                              ? 'Guardando...'
                              : (_sourceTab == 0
                                    ? 'Subir a la Biblioteca'
                                    : 'Registrar Enlace'),
                          style: const TextStyle(
                            fontFamily: CauceTheme.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 16,
                              color: CauceColors.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontFamily: CauceTheme.bodyFont,
                                  fontSize: 12,
                                  height: 1.3,
                                  color: CauceColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
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

class _SourceTabs extends StatelessWidget {
  const _SourceTabs({required this.tab, required this.onChanged});

  final int tab;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SourceTabButton(
              icon: Icons.upload_file,
              label: 'Archivo Local',
              selected: tab == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _SourceTabButton(
              icon: Icons.link,
              label: 'URL / Enlace',
              selected: tab == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceTabButton extends StatelessWidget {
  const _SourceTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? CauceColors.creamPrimary
                    : CauceColors.creamOnSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? CauceColors.creamOnSurface
                        : CauceColors.creamOnSurfaceVariant,
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

class _FilePanel extends StatelessWidget {
  const _FilePanel({
    required this.bytes,
    required this.fileName,
    required this.fileSize,
    required this.mediaType,
    required this.nameController,
    required this.onPick,
  });

  final Uint8List? bytes;
  final String fileName;
  final int fileSize;
  final String? mediaType;
  final TextEditingController nameController;
  final VoidCallback onPick;

  String? get _readableSize {
    const kb = 1024;
    const mb = 1024 * 1024;
    if (fileSize <= 0) return null;
    if (fileSize < mb) return '${(fileSize / kb).toStringAsFixed(0)} KB';
    return '${(fileSize / mb).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CauceColors.creamSurfaceContainerHighest,
          width: 1.4,
        ),
      ),
      child: Column(
        children: [
          if (bytes != null && mediaType == 'image') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _FilePlaceholder(),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (bytes != null && mediaType == 'video') ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CauceColors.creamSurfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.movie,
                    size: 32,
                    color: CauceColors.creamSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: CauceTheme.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CauceColors.creamOnSurface,
                          ),
                        ),
                        if (_readableSize != null)
                          Text(
                            'Video - $_readableSize',
                            style: TextStyle(
                              fontFamily: CauceTheme.bodyFont,
                              fontSize: 11,
                              color: CauceColors.creamOnSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else if (mediaType == 'pdf') ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CauceColors.creamSurfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.picture_as_pdf,
                    size: 32,
                    color: CauceColors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: CauceTheme.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CauceColors.creamOnSurface,
                          ),
                        ),
                        if (_readableSize != null)
                          Text(
                            'Documento PDF - $_readableSize',
                            style: TextStyle(
                              fontFamily: CauceTheme.bodyFont,
                              fontSize: 11,
                              color: CauceColors.creamOnSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            const _FilePlaceholder(),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              backgroundColor: CauceColors.creamSurfaceContainerHigh,
              foregroundColor: CauceColors.creamSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add_photo_alternate, size: 20),
            label: Text(
              bytes == null ? 'Explorar Archivo' : 'Cambiar Archivo',
              style: const TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Nombre (opcional)',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: CauceColors.creamOnSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: nameController,
            builder: (context, value, _) => TextField(
              controller: nameController,
              style: const TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.badge, size: 18),
                hintText: fileName.isEmpty
                    ? 'Como se mostrara en la sala'
                    : null,
                // El aviso solo aparece si el nombre excede el limite
                // del backend (255 caracteres).
                suffixText: value.text.length > 255 ? 'max 255' : null,
                errorMaxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Formatos permitidos, una linea por familia.
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Imagenes: PNG, JPG, GIF, WebP',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 11,
                  color: CauceColors.creamOnSurfaceVariant,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Videos: MP4, WebM, OGG, MOV, MKV',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 11,
                  color: CauceColors.creamOnSurfaceVariant,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Documentos: PDF',
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 11,
                  color: CauceColors.creamOnSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tamano maximo por archivo 200MB',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 11,
              color: CauceColors.creamOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePlaceholder extends StatelessWidget {
  const _FilePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: CauceColors.creamPrimaryFixed,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.cloud_upload,
            size: 30,
            color: CauceColors.creamPrimary,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Selecciona una imagen o un video',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: CauceTheme.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: CauceColors.creamOnSurface,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'El archivo se sube al servidor de la sala; el nombre del sistema '
          'se conserva como respaldo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: CauceTheme.bodyFont,
            fontSize: 12,
            color: CauceColors.creamOnSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _UrlPanel extends StatelessWidget {
  const _UrlPanel({
    required this.nameController,
    required this.urlController,
    required this.mimeController,
  });

  final TextEditingController nameController;
  final TextEditingController urlController;
  final TextEditingController mimeController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CauceColors.creamSurfaceContainerHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.rss_feed, size: 22, color: CauceColors.creamSecondary),
              SizedBox(width: 8),
              Text(
                'Enlace externo (http/https)',
                style: TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: CauceColors.creamOnSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Nombre *',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CauceColors.creamOnSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: nameController,
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.badge, size: 18),
              hintText: 'Como se mostrara en la sala',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'URL *',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CauceColors.creamOnSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: urlController,
            keyboardType: TextInputType.url,
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.stream, size: 18),
              hintText: 'https://ejemplo.org/contenido.mp4',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Descripcion (opcional)',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CauceColors.creamOnSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: mimeController,
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
            ),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.notes, size: 18),
              hintText: 'Describe el contenido del enlace',
            ),
          ),
        ],
      ),
    );
  }
}
