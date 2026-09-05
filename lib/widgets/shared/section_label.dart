import 'package:flutter/material.dart';
import 'text_style_cache.dart';

import '../../services/theme_service.dart';

/// A small ALL-CAPS section label used to title sub-sections in deck panels
/// and media views (e.g. "CHURCH ALERT & NOTICE PRESETS", "VIDEO CONTROLS").
///
/// Replaces the repeated `Text(…, OutfitStyle.get(11pt, w800, letterSpacing 1.0))`
/// blocks across deck files.
class SectionLabel extends StatelessWidget {
  final String text;
  final double fontSize;
  final double letterSpacing;
  final FontWeight fontWeight;
  final bool isUppercase;

  const SectionLabel(
    this.text, {
    super.key,
    this.fontSize = 11.0,
    this.letterSpacing = 1.0,
    this.fontWeight = FontWeight.w800,
    this.isUppercase = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      isUppercase ? text.toUpperCase() : text,
      style: OutfitStyle.get(
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: colors.textSecondary,
      ),
    );
  }
}
