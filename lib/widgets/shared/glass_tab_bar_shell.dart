import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

/// Shared frosted-glass container for tab bars used by Media Library and
/// Service Deck views. Eliminates the duplicated Container + BoxDecoration
/// pattern across both views.
class GlassTabBarShell extends StatelessWidget {
  final List<Widget> children;

  const GlassTabBarShell({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(isDark ? 80 : 120),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.border.withAlpha(isDark ? 30 : 20),
        ),
      ),
      child: Row(
        children: children,
      ),
    );
  }
}
