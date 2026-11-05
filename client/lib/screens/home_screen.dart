import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/experience.dart';
import '../services/google_drive_service.dart';
import '../widgets/category_row.dart';
import '../widgets/river_loading_indicator.dart';
import 'experience_content_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GoogleDriveService _driveService = GoogleDriveService();
  List<Category> _categories = [];
  List<List<FocusNode>> _expFocusGrid = [];
  List<ScrollController> _hScrollControllers = [];
  final ScrollController _verticalScrollController = ScrollController();
  final List<GlobalKey> _categoryKeys = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  void _onExperienceSelected(Experience experience) {
    if (experience.type == ExperienceType.simple) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExperienceContentScreen(experience: experience),
        ),
      );
    }
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final categories = await _driveService.fetchCatalog();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoryKeys
          ..clear()
          ..addAll(categories.map((_) => GlobalKey()));
        _expFocusGrid = categories.map((cat) =>
          List.generate(cat.experiences.length, (_) => FocusNode())
        ).toList();
        _hScrollControllers = categories.map((_) => ScrollController()).toList();
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

  @override
  void dispose() {
    _verticalScrollController.dispose();
    for (final row in _expFocusGrid) {
      for (final node in row) {
        node.dispose();
      }
    }
    for (final ctrl in _hScrollControllers) {
      ctrl.dispose();
    }
    _driveService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: _buildBody(),
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
              height: MediaQuery.of(context).size.height * 0.4,
              fit: BoxFit.contain,
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.03),
            const Text(
              'Cargando contenido...',
              style: TextStyle(color: Colors.white54, fontSize: 20, letterSpacing: 1),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.04),
            const RiverLoadingIndicator(
  width: 300,
  height: 14,
),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFF1565C0), size: 80),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 24),
            _RetryButton(onRetry: _loadCatalog),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: SingleChildScrollView(
            controller: _verticalScrollController,
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: _categories.asMap().entries.map((e) {
                final catIndex = e.key;
                final rowNodes = _expFocusGrid.length > catIndex
                    ? _expFocusGrid[catIndex]
                    : <FocusNode>[];
                final isLast = catIndex == _categories.length - 1;

                final prevNodes = catIndex > 0
                    ? _expFocusGrid[catIndex - 1]
                    : null;
                final nextNodes = !isLast && _expFocusGrid.length > catIndex + 1
                    ? _expFocusGrid[catIndex + 1]
                    : null;

                final List<VoidCallback?> upCbs;
                if (catIndex == 0) {
                  upCbs = rowNodes.map((_) => null).toList();
                } else if (prevNodes != null && prevNodes.isNotEmpty) {
                  final targetNode = prevNodes[0];
                  final targetCtrl = _hScrollControllers[catIndex - 1];
                  upCbs = rowNodes.map((_) => () {
                    if (targetCtrl.hasClients) targetCtrl.jumpTo(0);
                    targetNode.requestFocus();
                    _scrollIntoView(targetNode);
                  }).toList();
                } else {
                  upCbs = rowNodes.map((_) => null).toList();
                }

                final List<VoidCallback?> downCbs;
                if (nextNodes != null && nextNodes.isNotEmpty) {
                  final targetNode = nextNodes[0];
                  final targetCtrl = _hScrollControllers[catIndex + 1];
                  downCbs = rowNodes.map((_) => () {
                    if (targetCtrl.hasClients) targetCtrl.jumpTo(0);
                    targetNode.requestFocus();
                    _scrollIntoView(targetNode);
                  }).toList();
                } else {
                  downCbs = rowNodes.map((_) => null).toList();
                }

                return CategoryRow(
                  key: _categoryKeys[catIndex],
                  category: e.value,
                  onExperienceSelected: _onExperienceSelected,
                  initialFocus: catIndex == 0,
                  focusNodes: rowNodes,
                  upCallbacks: upCbs,
                  downCallbacks: downCbs,
                  scrollController: _hScrollControllers[catIndex],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

void _scrollIntoView(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCategoryRow(node);
    });
  }

  void _scrollToCategoryRow(FocusNode node) {
    for (int i = 0; i < _expFocusGrid.length; i++) {
      if (_expFocusGrid[i].contains(node) && i < _categoryKeys.length) {
        final key = _categoryKeys[i];
        if (key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            alignment: 0.0,
            duration: const Duration(milliseconds: 200),
          );
        }
        break;
      }
    }
  }

  Widget _buildTopBar() {
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
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final VoidCallback onRetry;

  const _RetryButton({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onRetry,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1565C0),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      ),
      child: const Text('Reintentar',
          style: TextStyle(color: Colors.white, fontSize: 20)),
    );
  }
}
