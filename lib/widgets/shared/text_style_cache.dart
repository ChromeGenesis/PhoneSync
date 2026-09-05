import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Unified cache key generator for font style caches.
String _buildCacheKey({
  required double fontSize,
  required FontWeight fontWeight,
  FontStyle? fontStyle,
  Color? color,
  Color? backgroundColor,
  double? height,
  double? letterSpacing,
  TextDecoration? decoration,
  List<Shadow>? shadows,
}) {
  final buf = StringBuffer(fontSize.toStringAsFixed(1));
  buf.write(':');
  buf.write(fontWeight.value);
  if (fontStyle != null) {
    buf.write(':');
    buf.write(fontStyle.name);
  }
  if (color != null) {
    buf.write(':c');
    buf.write(color.toARGB32());
  }
  if (backgroundColor != null) {
    buf.write(':bg');
    buf.write(backgroundColor.toARGB32());
  }
  if (height != null) {
    buf.write(':h');
    buf.write(height.toStringAsFixed(2));
  }
  if (letterSpacing != null) {
    buf.write(':ls');
    buf.write(letterSpacing.toStringAsFixed(2));
  }
  if (decoration != null) {
    buf.write(':dec');
    buf.write(decoration.hashCode);
  }
  if (shadows != null && shadows.isNotEmpty) {
    buf.write(':sh');
    for (final s in shadows) {
      buf.write(s.color.toARGB32());
      buf.write(s.blurRadius.toStringAsFixed(1));
    }
  }
  return buf.toString();
}

/// Generic font style cache that eliminates duplication across font families.
///
/// Pre-warms base font styles per [FontWeight] so that color, size, and
/// decoration updates are pure synchronous `.copyWith()` operations.
/// This eliminates GoogleFonts FOUT (Flash of Unstyled/Invisible Text).
class FontStyleCache {
  final TextStyle Function({FontWeight fontWeight}) _fontBuilder;
  final Map<FontWeight, TextStyle> _baseStyles = {};
  final Map<String, TextStyle> _cache = {};

  FontStyleCache({
    required TextStyle Function({FontWeight fontWeight}) fontBuilder,
    List<FontWeight> weights = const [
      FontWeight.w300,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
      FontWeight.w900,
    ],
  }) : _fontBuilder = fontBuilder {
    for (final weight in weights) {
      _baseStyles[weight] = fontBuilder(fontWeight: weight);
    }
  }

  TextStyle get({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    FontStyle? fontStyle,
    Color? color,
    Color? backgroundColor,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    List<Shadow>? shadows,
  }) {
    final key = _buildCacheKey(
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      color: color,
      backgroundColor: backgroundColor,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
      shadows: shadows,
    );
    final cached = _cache[key];
    if (cached != null) return cached;

    final base = _baseStyles[fontWeight] ?? _fontBuilder(fontWeight: fontWeight);
    final style = base.copyWith(
      fontSize: fontSize,
      fontStyle: fontStyle,
      color: color,
      backgroundColor: backgroundColor,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
      shadows: shadows,
    );
    _cache[key] = style;
    return style;
  }

  void clear() => _cache.clear();
}

/// Centralized cache for frequently-used Outfit TextStyle objects.
class OutfitStyle {
  OutfitStyle._();

  static final cache = FontStyleCache(
    fontBuilder: ({FontWeight fontWeight = FontWeight.w400}) =>
        GoogleFonts.outfit(fontWeight: fontWeight),
  );

  static TextStyle get({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    FontStyle? fontStyle,
    Color? color,
    Color? backgroundColor,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    List<Shadow>? shadows,
  }) => cache.get(
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    color: color,
    backgroundColor: backgroundColor,
    height: height,
    letterSpacing: letterSpacing,
    decoration: decoration,
    shadows: shadows,
  );

  static void clear() => cache.clear();
}

/// Centralized cache for frequently-used Fira Code (monospaced) TextStyle objects.
class FiraCodeStyle {
  FiraCodeStyle._();

  static final cache = FontStyleCache(
    fontBuilder: ({FontWeight fontWeight = FontWeight.w400}) =>
        GoogleFonts.firaCode(fontWeight: fontWeight),
    weights: [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700],
  );

  static TextStyle get({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    FontStyle? fontStyle,
    Color? color,
    Color? backgroundColor,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    List<Shadow>? shadows,
  }) => cache.get(
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    color: color,
    backgroundColor: backgroundColor,
    height: height,
    letterSpacing: letterSpacing,
    decoration: decoration,
    shadows: shadows,
  );

  static void clear() => cache.clear();
}
