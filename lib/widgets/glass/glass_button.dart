import 'package:flutter/material.dart';
import '../shared/text_style_cache.dart';

import '../../services/theme_service.dart';
import '../shared/hover_builder.dart';

/// A sleek frosted glass button with glow & hover animations.
class GlassButton extends StatelessWidget {
  final Widget? icon;
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onSecondaryTap;
  final String? tooltip;
  final Color? color;
  final Color? textColor;
  final bool isPrimary;
  final bool isDanger;
  final bool isSuccess;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double fontSize;

  const GlassButton({
    super.key,
    this.icon,
    required this.label,
    this.onPressed,
    this.onSecondaryTap,
    this.tooltip,
    this.color,
    this.textColor,
    this.isPrimary = false,
    this.isDanger = false,
    this.isSuccess = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    this.borderRadius = 10.0,
    this.fontSize = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (onPressed == null && onSecondaryTap == null) {
      final disabledBtn = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: colors.surfaceGlass.withAlpha(20),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: colors.borderSubtle, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: colors.textMuted.withAlpha(140),
                  size: fontSize + 2,
                ),
                child: icon!,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: OutfitStyle.get(
                color: colors.textMuted.withAlpha(140),
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );

      if (tooltip != null) {
        return Tooltip(message: tooltip!, child: disabledBtn);
      }
      return disabledBtn;
    }

    Widget btn = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, isHovered) {
        Color bg;
        Color border;
        Color text;

        if (isPrimary) {
          bg = isHovered ? colors.textGold : colors.goldPrimary;
          border = colors.goldPrimary;
          text = const Color(0xFF0A0A0A);
        } else if (isDanger) {
          bg = isHovered
              ? colors.roseDanger.withAlpha(180)
              : colors.roseDanger.withAlpha(120);
          border = colors.roseDanger;
          text = Colors.white;
        } else if (isSuccess) {
          bg = isHovered ? colors.emeraldLive : const Color(0xFF059669);
          border = colors.emeraldLive;
          text = Colors.white;
        } else {
          bg =
              color ??
              colors.surfaceGlass.withAlpha(isHovered ? 50 : 20);
          border = isHovered
              ? colors.borderGlass
              : colors.borderSubtle;
          text = textColor ?? colors.textPrimary;
        }

        return GestureDetector(
          onTap: onPressed,
          onSecondaryTap: onSecondaryTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            clipBehavior: Clip.antiAlias,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(color: border, width: 1.0),
                boxShadow: isHovered && isPrimary
                    ? [
                        BoxShadow(
                          color: colors.goldGlow,
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    IconTheme(
                      data: IconThemeData(color: text, size: fontSize + 2),
                      child: icon!,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: OutfitStyle.get(
                      color: text,
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// Glass icon button with hover animations.
class GlassIconButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onPressed;
  final VoidCallback? onSecondaryTap;
  final String? tooltip;
  final Color? color;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final bool isActive;
  final Color? activeColor;

  const GlassIconButton({
    super.key,
    this.icon,
    this.iconWidget,
    this.onPressed,
    this.onSecondaryTap,
    this.tooltip,
    this.color,
    this.iconColor,
    this.size = 34.0,
    this.iconSize = 16.0,
    this.isActive = false,
    this.activeColor,
  }) : assert(icon != null || iconWidget != null, 'Either icon or iconWidget must be provided');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget btn = HoverBuilder(
      cursor: (onPressed != null || onSecondaryTap != null)
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      builder: (context, isHovered) {
        final bg = isActive
            ? (activeColor ?? colors.goldPrimary)
            : (color ??
                  colors.surfaceGlass.withAlpha(isHovered ? 50 : 20));

        final border = isActive
            ? (activeColor ?? colors.goldPrimary)
            : (isHovered
                  ? colors.borderGlass
                  : colors.borderSubtle);

        final iconCol = isActive
            ? const Color(0xFF0A0A0A)
            : (iconColor ??
                  (isHovered ? colors.textPrimary : colors.textSecondary));

        return GestureDetector(
          onTap: onPressed,
          onSecondaryTap: onSecondaryTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9.0),
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(9.0),
                border: Border.all(color: border, width: 1.0),
              ),
              child: Center(
                child: iconWidget ??
                    Icon(icon, size: iconSize, color: iconCol),
              ),
            ),
          ),
        );
      },
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}
