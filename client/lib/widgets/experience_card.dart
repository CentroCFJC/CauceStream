import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/experience.dart';

class ExperienceCard extends StatelessWidget {
  final Experience experience;
  final bool isFocused;

  const ExperienceCard({
    super.key,
    required this.experience,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    final cardWidth = sh * 0.18;
    final cardHeight = cardWidth * 1.45;

    return Container(
      width: cardWidth,
      height: cardHeight,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: isFocused
            ? Border.all(color: Colors.white, width: 3)
            : Border.all(color: Colors.transparent, width: 3),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF42A5F5).withAlpha(100),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCover(),
            _buildGradientOverlay(cardHeight),
            _buildTitle(sh),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    if (experience.coverUrl != null) {
      return CachedNetworkImage(
        imageUrl: experience.coverUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildPlaceholder(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1D34), Color(0xFF0A1628)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.explore_outlined, color: Color(0xFF1565C0), size: 52),
      ),
    );
  }

  Widget _buildGradientOverlay(double cardHeight) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: cardHeight * 0.4,
      child: IgnorePointer(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Color(0xEE0A1628),
                Color(0xCC0A1628),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(double sh) {
    return Positioned(
      bottom: 12,
      left: 12,
      right: 12,
      child: Text(
        experience.name,
        style: TextStyle(
          color: Colors.white,
          fontSize: sh * 0.019,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 4),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}
