import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

/// Style configuration for glassmorphic cards and containers.
class GlassCardStyle {
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final int backgroundAlpha;
  final int borderAlpha;
  final double borderWidth;
  final double blurSigma;
  final List<BoxShadow>? boxShadow;

  const GlassCardStyle({
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 16.0,
    this.backgroundAlpha = 30,
    this.borderAlpha = 35,
    this.borderWidth = 1.0,
    this.blurSigma = 12.0,
    this.boxShadow,
  });

  static const standard = GlassCardStyle();

  static const feature = GlassCardStyle(
    padding: EdgeInsets.all(18.0),
    borderRadius: 18.0,
    backgroundAlpha: 45,
    borderAlpha: 55,
    borderWidth: 1.2,
    blurSigma: 16.0,
  );

  static const compact = GlassCardStyle(
    padding: EdgeInsets.all(10.0),
    borderRadius: 12.0,
    backgroundAlpha: 25,
    borderAlpha: 30,
    borderWidth: 0.8,
    blurSigma: 0.0,
  );
}

/// A premium glassmorphic card container with backdrop blur, customizable tint, and frosted borders.
class GlassMorphicCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final double? blurSigma;
  final List<BoxShadow>? boxShadow;
  final GlassCardStyle style;
  final VoidCallback? onTap;
  final bool isSelected;
  final Color? selectedBorderColor;

  const GlassMorphicCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.blurSigma,
    this.boxShadow,
    this.style = GlassCardStyle.standard,
    this.onTap,
    this.isSelected = false,
    this.selectedBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final radius = borderRadius ?? style.borderRadius;

    // Dark mode: keep the fill barely-there so background color bleeds
    // through the card edges (liquid-glass corner effect).
    final defaultBg = isDark
        ? colors.surface.withAlpha(style.backgroundAlpha)
        : Colors.white.withAlpha(style.backgroundAlpha + 160);

    final defaultBorder = isDark
        ? Colors.white.withAlpha(style.borderAlpha)
        : Colors.black.withAlpha(style.borderAlpha);

    final effectiveBorderColor = isSelected
        ? (selectedBorderColor ?? colors.goldPrimary)
        : (borderColor ?? defaultBorder);

    final effectiveBg = isSelected
        ? (isDark
              ? colors.goldPrimary.withAlpha(40)
              : colors.goldPrimary.withAlpha(25))
        : (backgroundColor ?? defaultBg);

    final effectiveShadow = isSelected
        ? [
            BoxShadow(
              color: colors.goldGlow,
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            ...?boxShadow,
          ]
        : boxShadow ?? style.boxShadow;

    Widget body = Container(
      padding: padding ?? style.padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: effectiveBorderColor,
          width: isSelected ? 1.5 : style.borderWidth,
        ),
        boxShadow: effectiveShadow,
      ),
      child: child,
    );

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: body,
    );

    if (onTap != null) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: content),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}
