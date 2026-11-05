import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/browser_item.dart';
import '../models/experience.dart';
import '../models/video_item.dart';
import '../services/google_drive_service.dart';
import '../widgets/browser_row.dart';
import '../widgets/river_loading_indicator.dart';
import 'player_screen.dart';

class ExperienceContentScreen extends StatefulWidget {
  final Experience? experience;
  final String? folderId;
  final String? folderName;

  const ExperienceContentScreen({
    super.key,
    this.experience,
    this.folderId,
    this.folderName,
  });

  @override
  State<ExperienceContentScreen> createState() => _ExperienceContentScreenState();
}

class _ExperienceContentScreenState extends State<ExperienceContentScreen> {
  final GoogleDriveService _driveService = GoogleDriveService();
  List<BrowserItem> _folders = [];
  List<BrowserItem> _files = [];
  bool _loading = true;
  String? _error;

  final List<FocusNode> _folderFocusNodes = [];
  final List<FocusNode> _fileFocusNodes = [];
  final ScrollController _folderScrollController = ScrollController();
  final ScrollController _fileScrollController = ScrollController();

  String get _title => widget.experience?.name ?? widget.folderName ?? 'Contenido';
  String get _currentFolderId => widget.experience?.driveFolderId ?? widget.folderId!;

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  Future<void> _loadContents() async {
    try {
      final items = await _driveService.listContents(_currentFolderId);
      if (!mounted) return;
      setState(() {
        _folders = items.where((i) => i.isFolder).toList();
        _files = items.where((i) => !i.isFolder).toList();
        _folderFocusNodes
          ..clear()
          ..addAll(_folders.map((_) => FocusNode()));
        _fileFocusNodes
          ..clear()
          ..addAll(_files.map((_) => FocusNode()));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar el contenido';
        _loading = false;
      });
    }
  }

  void _onItemSelected(BrowserItem item) {
    if (item.isFolder) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExperienceContentScreen(
            folderId: item.folderId,
            folderName: item.name,
          ),
        ),
      );
    } else {
      final video = VideoItem(
        id: item.id,
        name: item.name,
        fileUrl: item.fileUrl!,
        thumbnailUrl: item.thumbnailUrl,
        type: item.fileType ?? 'video',
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerScreen(video: video)),
      );
    }
  }

  @override
  void dispose() {
    _driveService.dispose();
    _folderScrollController.dispose();
    _fileScrollController.dispose();
    for (final node in _folderFocusNodes) {
      node.dispose();
    }
    for (final node in _fileFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                 event.logicalKey == LogicalKeyboardKey.gameButtonB ||
                 event.logicalKey == LogicalKeyboardKey.goBack ||
                 event.logicalKey == LogicalKeyboardKey.backspace)) {
              if (Navigator.canPop(context)) Navigator.pop(context);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              Expanded(
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final sh = MediaQuery.of(context).size.height;
    return Container(
      height: sh * 0.09,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1D34), Color(0xFF0A1628)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          Image.network(
            'https://res.cloudinary.com/dqgd5r847/image/upload/v1781198321/logo_cauce_blanco_completo_kgcj3s.png',
            height: sh * 0.055,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          Text(
            _title,
            style: TextStyle(
              color: Colors.white,
              fontSize: sh * 0.026,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              'https://res.cloudinary.com/dqgd5r847/image/upload/v1781198321/logo_cauce_blanco_completo_kgcj3s.png',
              height: MediaQuery.of(context).size.height * 0.12,
              fit: BoxFit.contain,
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.04),
            const RiverLoadingIndicator(),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.white70, fontSize: 22),
        ),
      );
    }

    if (_folders.isEmpty && _files.isEmpty) {
      return const Center(
        child: Text(
          'No hay archivos en esta carpeta',
          style: TextStyle(color: Colors.white54, fontSize: 20),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_folders.isNotEmpty)
            BrowserRow(
              title: 'Carpetas',
              items: _folders,
              initialFocus: true,
              focusNodes: _folderFocusNodes,
              scrollController: _folderScrollController,
              onItemSelected: _onItemSelected,
              downCallbacks: _files.isNotEmpty && _fileFocusNodes.isNotEmpty
                  ? _folders.map((_) => () {
                      _fileScrollController.jumpTo(0);
                      _fileFocusNodes[0].requestFocus();
                    }).toList()
                  : null,
            ),
          if (_files.isNotEmpty)
            BrowserRow(
              title: 'Archivos',
              items: _files,
              initialFocus: _folders.isEmpty,
              focusNodes: _fileFocusNodes,
              scrollController: _fileScrollController,
              onItemSelected: _onItemSelected,
              upCallbacks: _folders.isNotEmpty && _folderFocusNodes.isNotEmpty
                  ? _files.map((_) => () {
                      _folderScrollController.jumpTo(0);
                      _folderFocusNodes[0].requestFocus();
                    }).toList()
                  : null,
            ),
        ],
      ),
    );
  }
}
