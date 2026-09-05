import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../shared/text_style_cache.dart';

/// Standardized mini-badge / metadata tag pill for decks, cards, and previews.
///
/// Use for duration, resolution, loop count, format tags, and speeds instead of
/// ad-hoc container declarations.
class InfoPill extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final FontWeight fontWeight;
  final double borderRadius;

  const InfoPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.0),
    this.fontSize = 8.5,
    this.fontWeight = FontWeight.bold,
    this.borderRadius = 4.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    final effectiveColor = color ?? colors.textSecondary;
    final effectiveBg = color != null
        ? color!.withAlpha(isDark ? 35 : 25)
        : colors.surface.withAlpha(isDark ? 100 : 150);
    final effectiveBorder = color != null
        ? color!.withAlpha(isDark ? 70 : 50)
        : colors.border.withAlpha(isDark ? 40 : 25);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: effectiveBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: effectiveColor),
            const SizedBox(width: 3.5),
          ],
          Text(
            label,
            style: OutfitStyle.get(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: effectiveColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
