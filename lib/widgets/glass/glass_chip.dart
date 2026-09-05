import 'package:flutter/material.dart';
import '../shared/text_style_cache.dart';

import '../../services/theme_service.dart';

/// Glass Chip for tags, presets, and recent selections.
class GlassChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? icon;
  final int? count;

  const GlassChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final bg = isSelected
        ? colors.goldPrimary.withAlpha(45)
        : colors.border.withAlpha(15);

    final border = isSelected
        ? colors.goldPrimary
        : colors.border.withAlpha(25);

    final textCol = isSelected ? colors.goldPrimary : colors.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  IconTheme(
                    data: IconThemeData(color: textCol, size: 13),
                    child: icon!,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: OutfitStyle.get(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: textCol,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4.5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: textCol.withAlpha(isSelected ? 45 : 25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$count',
                      style: OutfitStyle.get(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: textCol,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
