import 'package:flutter/material.dart';
import 'text_style_cache.dart';

import '../../services/theme_service.dart';

/// Generic empty-state placeholder for media grids (videos, photos, etc.).
///
/// Replaces the two near-identical `Center > Column > Icon + Text + Text`
/// blocks that were copy-pasted in `media_photos_grid.dart` and
/// `media_videos_grid.dart`.
class MediaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const MediaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: colors.textSecondary.withAlpha(75)),
          const SizedBox(height: 12),
          Text(
            title,
            style: OutfitStyle.get(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: OutfitStyle.get(
              fontSize: 12,
              color: colors.textSecondary.withAlpha(145),
            ),
          ),
        ],
      ),
    );
  }
}
