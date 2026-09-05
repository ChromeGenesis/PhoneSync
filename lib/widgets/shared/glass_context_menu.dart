import 'package:flutter/material.dart';
import 'text_style_cache.dart';

import '../../services/theme_service.dart';

/// Single item in a glass context menu.
class GlassContextMenuItem<T> {
  final T value;
  final String label;
  final IconData icon;
  final Color? iconColor;
  final Color? textColor;
  final bool isDanger;

  const GlassContextMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.iconColor,
    this.textColor,
    this.isDanger = false,
  });
}

/// Displays an instantaneous, non-blocking glassmorphic context menu at [globalPos].
///
/// Designed to replace Flutter's default Material `showMenu` with a fast
/// 100ms micro-transition and immediate barrier dismissal on outside click.
Future<T?> showGlassContextMenu<T>({
  required BuildContext context,
  required Offset globalPos,
  required List<GlassContextMenuItem<T>> items,
  double width = 148.0,
}) {
  final colors = context.colors;
  final isDark = context.isDark;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss Context Menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 100),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final screenSize = MediaQuery.of(ctx).size;
      final menuHeight = (items.length * 36.0) + 8.0;

      double left = globalPos.dx;
      double top = globalPos.dy;

      if (left + width > screenSize.width - 12) {
        left = screenSize.width - width - 12;
      }
      if (top + menuHeight > screenSize.height - 12) {
        top = screenSize.height - menuHeight - 12;
      }

      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: width,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF18181B) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.borderSubtle,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 160 : 40),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: items.map((item) {
                        final effectiveIconColor = item.iconColor ??
                            (item.isDanger ? colors.roseDanger : colors.goldPrimary);
                        final effectiveTextColor = item.textColor ??
                            (item.isDanger ? colors.roseDanger : colors.foreground);

                        return InkWell(
                          onTap: () => Navigator.of(ctx).pop(item.value),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(item.icon, size: 14, color: effectiveIconColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: OutfitStyle.get(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: effectiveTextColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
