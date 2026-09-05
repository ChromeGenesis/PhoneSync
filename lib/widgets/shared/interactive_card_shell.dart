import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import 'hover_builder.dart';

/// Standard interactive shell for preset, item, and cue cards.
///
/// Encapsulates hover state animation, active/selected highlight border,
/// glowing accent shadow, and background tint calculations.
class InteractiveCardShell extends StatelessWidget {
  final Widget child;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Duration duration;

  const InteractiveCardShell({
    super.key,
    required this.child,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
    this.accentColor,
    this.padding = const EdgeInsets.all(12),
    this.margin,
    this.borderRadius = 12.0,
    this.duration = const Duration(milliseconds: 180),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final effectiveAccent = accentColor ?? colors.primary;

    return HoverBuilder(
      builder: (context, isHovered) {
        final effectiveBg = isSelected
            ? effectiveAccent.withAlpha(isDark ? 40 : 50)
            : isHovered
            ? colors.surface.withAlpha(isDark ? 140 : 180)
            : colors.surface.withAlpha(isDark ? 120 : 160);

        final effectiveBorder = isSelected
            ? effectiveAccent
            : isHovered
            ? colors.border.withAlpha(isDark ? 65 : 45)
            : colors.border.withAlpha(isDark ? 30 : 20);

        final effectiveShadow = isSelected
            ? [
                BoxShadow(
                  color: effectiveAccent.withAlpha(isDark ? 100 : 80),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null;

        return MouseRegion(
          cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            child: AnimatedContainer(
              duration: duration,
              margin: margin,
              padding: padding,
              decoration: BoxDecoration(
                color: effectiveBg,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: effectiveBorder,
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: effectiveShadow,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
