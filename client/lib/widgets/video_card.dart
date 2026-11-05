import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video_item.dart';

class VideoCard extends StatefulWidget {
  final VideoItem video;
  final double width;
  final double height;
  final bool isFocused;

  const VideoCard({
    super.key,
    required this.video,
    this.width = 420,
    this.height = 260,
    this.isFocused = false,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> with SingleTickerProviderStateMixin {
  late AnimationController _marqueeController;

  @override
  void initState() {
    super.initState();
    _marqueeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    if (widget.isFocused) {
      _marqueeController.duration = _calculateDuration();
      _marqueeController.repeat();
    }
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused && !_marqueeController.isAnimating) {
      _marqueeController.duration = _calculateDuration();
      _marqueeController.repeat();
    } else if (!widget.isFocused && _marqueeController.isAnimating) {
      _marqueeController.stop();
      _marqueeController.reset();
    }
  }

  static const _marqueeStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white);
  static const _separator = '|';
  static const _gapSize = 16.0;

  double _measureTextWidth(String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _marqueeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  Duration _calculateDuration() {
    const speed = 50.0;
    final totalWidth = _measureTextWidth(widget.video.name) + _measureTextWidth(_separator) + 2 * _gapSize;
    return Duration(milliseconds: (totalWidth / speed * 1000).toInt());
  }

  @override
  void dispose() {
    _marqueeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final effectiveWidth = widget.width == 420 ? screenWidth * 0.22 : widget.width;
    final effectiveHeight = effectiveWidth * (widget.height / widget.width);
    return Container(
      width: effectiveWidth,
      height: effectiveHeight,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: widget.isFocused
            ? Border.all(color: Colors.white, width: 3)
            : Border.all(color: Colors.transparent, width: 3),
        boxShadow: widget.isFocused
            ? [BoxShadow(
                color: Colors.white.withAlpha(80),
                blurRadius: 18,
                spreadRadius: 4,
              )]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildThumbnail(),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xCC0A1628),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  _typeIcon(widget.video.type),
                  size: 20,
                  color: const Color(0xFF42A5F5),
                ),
              ),
            ),
            _buildOverlay(effectiveHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(double cardHeight) {
    final overlayHeight = cardHeight * 0.25;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: overlayHeight,
        color: const Color(0xFF0A1628).withAlpha(190),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const textStyle = TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            );

            final textPainter = TextPainter(
              text: TextSpan(text: widget.video.name, style: textStyle),
              textDirection: TextDirection.ltr,
            )..layout();

            if (widget.isFocused && textPainter.width > constraints.maxWidth) {
              const pipe = '|';
              final pipeWidth = _measureTextWidth(pipe);
              final totalWidth = textPainter.width + pipeWidth + 2 * _gapSize;

              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: AnimatedBuilder(
                    animation: _marqueeController,
                    builder: (context, _) {
                      return Transform.translate(
                        offset: Offset(-_marqueeController.value * totalWidth, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(widget.video.name, style: textStyle, maxLines: 1, softWrap: false),
                            SizedBox(width: _gapSize),
                            Text(pipe, style: textStyle),
                            SizedBox(width: _gapSize),
                            Text(widget.video.name, style: textStyle, maxLines: 1, softWrap: false),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            }

            return Text(
              widget.video.name,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    if (widget.video.thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.video.thumbnailUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildPlaceholder(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade800,
      child: Center(
        child: Icon(_typeIcon(widget.video.type), color: Colors.grey, size: 56),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'gif':
        return Icons.gif_box;
      case 'pdf':
        return Icons.picture_as_pdf;
      default:
        return Icons.movie_outlined;
    }
  }
}
