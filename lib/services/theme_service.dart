import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'logger.dart';

class AppColors extends ThemeExtension<AppColors> {
  final Color scaffoldBackground;
  final Color surface;
  final Color surfaceGlass;
  final Color surfaceVariant;
  final Color borderGlass;
  final Color borderSubtle;
  final Color goldPrimary;
  final Color goldGlow;
  final Color orbSecondary;
  final Color emeraldLive;
  final Color roseDanger;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textGold;
  final Color divider;
  final Color inputBackground;
  final Color inputBorder;
  final Color liveBadgeBackground;
  final Color liveBadgeText;
  final bool isDark;

  const AppColors({
    required this.scaffoldBackground,
    required this.surface,
    required this.surfaceGlass,
    required this.surfaceVariant,
    required this.borderGlass,
    required this.borderSubtle,
    required this.goldPrimary,
    required this.goldGlow,
    required this.orbSecondary,
    required this.emeraldLive,
    required this.roseDanger,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textGold,
    required this.divider,
    required this.inputBackground,
    required this.inputBorder,
    required this.liveBadgeBackground,
    required this.liveBadgeText,
    required this.isDark,
  });

  @override
  ThemeExtension<AppColors> copyWith({
    Color? scaffoldBackground,
    Color? surface,
    Color? surfaceGlass,
    Color? surfaceVariant,
    Color? borderGlass,
    Color? borderSubtle,
    Color? goldPrimary,
    Color? goldGlow,
    Color? orbSecondary,
    Color? emeraldLive,
    Color? roseDanger,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textGold,
    Color? divider,
    Color? inputBackground,
    Color? inputBorder,
    Color? liveBadgeBackground,
    Color? liveBadgeText,
    bool? isDark,
  }) {
    return AppColors(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      surface: surface ?? this.surface,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      borderGlass: borderGlass ?? this.borderGlass,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      goldPrimary: goldPrimary ?? this.goldPrimary,
      goldGlow: goldGlow ?? this.goldGlow,
      orbSecondary: orbSecondary ?? this.orbSecondary,
      emeraldLive: emeraldLive ?? this.emeraldLive,
      roseDanger: roseDanger ?? this.roseDanger,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textGold: textGold ?? this.textGold,
      divider: divider ?? this.divider,
      inputBackground: inputBackground ?? this.inputBackground,
      inputBorder: inputBorder ?? this.inputBorder,
      liveBadgeBackground: liveBadgeBackground ?? this.liveBadgeBackground,
      liveBadgeText: liveBadgeText ?? this.liveBadgeText,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  ThemeExtension<AppColors> lerp(
    ThemeExtension<AppColors>? other,
    double t,
  ) {
    if (other is! AppColors) return this;
    return AppColors(
      scaffoldBackground: Color.lerp(
        scaffoldBackground,
        other.scaffoldBackground,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      borderGlass: Color.lerp(borderGlass, other.borderGlass, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      goldPrimary: Color.lerp(goldPrimary, other.goldPrimary, t)!,
      goldGlow: Color.lerp(goldGlow, other.goldGlow, t)!,
      orbSecondary: Color.lerp(orbSecondary, other.orbSecondary, t)!,
      emeraldLive: Color.lerp(emeraldLive, other.emeraldLive, t)!,
      roseDanger: Color.lerp(roseDanger, other.roseDanger, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textGold: Color.lerp(textGold, other.textGold, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      inputBorder: Color.lerp(inputBorder, other.inputBorder, t)!,
      liveBadgeBackground: Color.lerp(
        liveBadgeBackground,
        other.liveBadgeBackground,
        t,
      )!,
      liveBadgeText: Color.lerp(liveBadgeText, other.liveBadgeText, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

  // Convenience aliases for clean widget code
  Color get border => borderGlass;
  Color get primary => goldPrimary;
  Color get foreground => textPrimary;
  Color get live => emeraldLive;
}

/// A selectable accent palette that recolors the whole app chrome.
class AccentPreset {
  final String id;
  final String label;
  final Color darkPrimary;
  final Color darkGlow;
  final Color darkTextGold;
  final Color darkOrb;
  final Color lightPrimary;
  final Color lightGlow;
  final Color lightTextGold;
  final Color lightOrb;

  const AccentPreset({
    required this.id,
    required this.label,
    required this.darkPrimary,
    required this.darkGlow,
    required this.darkTextGold,
    required this.darkOrb,
    required this.lightPrimary,
    required this.lightGlow,
    required this.lightTextGold,
    required this.lightOrb,
  });

  static const amber = AccentPreset(
    id: 'amber',
    label: 'Amber',
    darkPrimary: Color(0xFFF59E0B), // Amber-500
    darkGlow: Color(0x50F59E0B),
    darkTextGold: Color(0xFFFBBF24), // Amber-400
    darkOrb: Color(0xFF312E81), // Indigo-900
    lightPrimary: Color(0xFFD97706), // Amber-600
    lightGlow: Color(0x40D97706),
    lightTextGold: Color(0xFFD97706),
    lightOrb: Color(0xFF3B82F6), // Blue-500
  );

  static const emerald = AccentPreset(
    id: 'emerald',
    label: 'Emerald',
    darkPrimary: Color(0xFF10B981), // Emerald-500
    darkGlow: Color(0x5010B981),
    darkTextGold: Color(0xFF34D399), // Emerald-400
    darkOrb: Color(0xFF0D9488), // Teal-600
    lightPrimary: Color(0xFF059669), // Emerald-600
    lightGlow: Color(0x40059669),
    lightTextGold: Color(0xFF059669),
    lightOrb: Color(0xFF10B981),
  );

  static const navy = AccentPreset(
    id: 'navy',
    label: 'Navy',
    darkPrimary: Color(0xFF60A5FA), // Blue-400
    darkGlow: Color(0x5060A5FA),
    darkTextGold: Color(0xFF93C5FD), // Blue-300
    darkOrb: Color(0xFF1E3A8A), // Blue-900
    lightPrimary: Color(0xFF2563EB), // Blue-600
    lightGlow: Color(0x402563EB),
    lightTextGold: Color(0xFF2563EB),
    lightOrb: Color(0xFF3B82F6),
  );

  static const crimson = AccentPreset(
    id: 'crimson',
    label: 'Crimson',
    darkPrimary: Color(0xFFFB7185), // Rose-400
    darkGlow: Color(0x50FB7185),
    darkTextGold: Color(0xFFFDA4AF), // Rose-300
    darkOrb: Color(0xFF9F1239), // Rose-800
    lightPrimary: Color(0xFFBE123C), // Rose-700
    lightGlow: Color(0x40BE123C),
    lightTextGold: Color(0xFFBE123C),
    lightOrb: Color(0xFFE11D48),
  );

  static const all = [amber, emerald, navy, crimson];

  static AccentPreset fromId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => amber);
}

class AppThemeService extends ChangeNotifier {
  static final AppThemeService instance = AppThemeService._();

  static const String _storageKey = 'phonesync_theme_mode';
  static const String _accentKey = 'phonesync_accent';

  /// Follow the OS by default. A desktop app that opens dark regardless of the
  /// user's system appearance is the most jarring default there is — a
  /// maximized window in light mode looks broken.
  ThemeMode _themeMode = ThemeMode.system;
  AccentPreset _accent = AccentPreset.amber;

  ThemeMode get themeMode => _themeMode;
  AccentPreset get accent => _accent;

  AppThemeService._() {
    _loadTheme();
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged = () {
      if (_themeMode == ThemeMode.system) {
        _syncWindowTheme();
        notifyListeners();
      }
    };
  }

  /// Explicitly initialize and load saved theme before first frame render
  Future<void> init() => _loadTheme();

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved != null) {
        if (saved == 'light') {
          _themeMode = ThemeMode.light;
        } else if (saved == 'system') {
          _themeMode = ThemeMode.system;
        } else {
          _themeMode = ThemeMode.dark;
        }
        _syncWindowTheme();
        notifyListeners();
      }
      final savedAccent = prefs.getString(_accentKey);
      if (savedAccent != null) {
        _accent = AccentPreset.fromId(savedAccent);
        notifyListeners();
      }
    } catch (e) {
      Logger.error('Error loading theme mode: $e');
    }
    // Sync even when nothing was saved: on first launch the OS appearance is
    // the source of truth and the window chrome has to match it.
    _syncWindowTheme();
  }

  Brightness get resolvedBrightness {
    if (_themeMode == ThemeMode.light) return Brightness.light;
    if (_themeMode == ThemeMode.dark) return Brightness.dark;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  bool get isDark => resolvedBrightness == Brightness.dark;

  void _syncWindowTheme() {
    try {
      windowManager.setBrightness(resolvedBrightness);
    } catch (_) {}
  }

  Future<void> setAccent(AccentPreset preset) async {
    _accent = preset;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accentKey, preset.id);
    } catch (e) {
      Logger.error('Error saving accent: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _syncWindowTheme();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = mode == ThemeMode.light
          ? 'light'
          : mode == ThemeMode.system
          ? 'system'
          : 'dark';
      await prefs.setString(_storageKey, modeStr);
    } catch (e) {
      Logger.error('Error saving theme mode: $e');
    }
  }

  static const darkColors = AppColors(
    scaffoldBackground: Color(0xFF000000), // Pure black
    surface: Color(0xFF0A0A0A), // Near-black
    surfaceGlass: Color(0xFF0A0A0A),
    surfaceVariant: Color(0xFF161616), // Lifted near-black
    borderGlass: Color(0x28FFFFFF), // 16% white
    borderSubtle: Color(0x1AFFFFFF), // 10% white
    goldPrimary: Color(0xFFF59E0B), // Amber-500
    goldGlow: Color(0x50F59E0B),
    orbSecondary: Color(0xFF312E81), // Indigo-900
    emeraldLive: Color(0xFF10B981), // Emerald-500
    roseDanger: Color(0xFFEF4444), // Red-500
    textPrimary: Color(0xFFF8FAFC), // Slate-50
    textSecondary: Color(0xFF94A3B8), // Slate-400
    textMuted: Color(0xFF64748B), // Slate-500
    textGold: Color(0xFFFBBF24), // Amber-400
    divider: Color(0x1AFFFFFF),
    inputBackground: Color(0xCC000000),
    inputBorder: Color(0x28FFFFFF),
    liveBadgeBackground: Color(0xFF10B981),
    liveBadgeText: Color(0xFF000000),
    isDark: true,
  );

  static const lightColors = AppColors(
    scaffoldBackground: Color(0xFFF1F5F9), // Slate-100
    surface: Color(0xFFFFFFFF), // Pure white
    surfaceGlass: Color(0xF0FFFFFF),
    surfaceVariant: Color(0xFFE2E8F0), // Slate-200
    borderGlass: Color(0x1F000000), // 12% black
    borderSubtle: Color(0x14000000), // 8% black
    goldPrimary: Color(0xFFD97706), // Amber-600
    goldGlow: Color(0x40D97706),
    orbSecondary: Color(0xFF3B82F6), // Blue-500
    emeraldLive: Color(0xFF059669), // Emerald-600
    roseDanger: Color(0xFFDC2626), // Red-600
    textPrimary: Color(0xFF0F172A), // Slate-900
    textSecondary: Color(0xFF475569), // Slate-600
    textMuted: Color(0xFF94A3B8), // Slate-400
    textGold: Color(0xFFD97706), // Amber-600
    divider: Color(0x14000000),
    inputBackground: Color(0xF5FFFFFF),
    inputBorder: Color(0x1F000000),
    liveBadgeBackground: Color(0xFF059669),
    liveBadgeText: Color(0xFFFFFFFF),
    isDark: false,
  );

  /// Base palettes with the currently selected accent applied.
  static AppColors get darkAccentColors =>
      darkColors.copyWith(
            goldPrimary: instance._accent.darkPrimary,
            goldGlow: instance._accent.darkGlow,
            textGold: instance._accent.darkTextGold,
            orbSecondary: instance._accent.darkOrb,
          )
          as AppColors;

  static AppColors get lightAccentColors =>
      lightColors.copyWith(
            goldPrimary: instance._accent.lightPrimary,
            goldGlow: instance._accent.lightGlow,
            textGold: instance._accent.lightTextGold,
            orbSecondary: instance._accent.lightOrb,
          )
          as AppColors;

  // ThemeData construction is expensive (GoogleFonts text theme, extensions).
  // Cache the built themes and invalidate on any theme notification so every
  // listener rebuild reuses one instance instead of building 4 fresh ThemeDatas.
  ThemeData? _darkThemeCache;
  ThemeData? _lightThemeCache;

  @override
  void notifyListeners() {
    _darkThemeCache = null;
    _lightThemeCache = null;
    super.notifyListeners();
  }

  static ThemeData get darkTheme =>
      instance._darkThemeCache ??= _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
    final c = darkAccentColors;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: c.scaffoldBackground,
      canvasColor: c.surface,
      cardColor: c.surface,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme.dark(
        primary: c.goldPrimary,
        secondary: c.emeraldLive,
        surface: c.surface,
        surfaceContainerHighest: c.surfaceVariant,
        error: c.roseDanger,
        onPrimary: c.scaffoldBackground,
        onSurface: c.textPrimary,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1),
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
      ),
      extensions: [c],
      useMaterial3: true,
    );
  }

  static ThemeData get lightTheme =>
      instance._lightThemeCache ??= _buildLightTheme();

  static ThemeData _buildLightTheme() {
    final c = lightAccentColors;
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: c.scaffoldBackground,
      canvasColor: c.surface,
      cardColor: c.surface,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme.light(
        primary: c.goldPrimary,
        secondary: c.emeraldLive,
        surface: c.surface,
        surfaceContainerHighest: c.surfaceVariant,
        error: c.roseDanger,
        onPrimary: Colors.white,
        onSurface: c.textPrimary,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1),
      cardTheme: const CardThemeData(clipBehavior: Clip.antiAlias),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
      ),
      extensions: [c],
      useMaterial3: true,
    );
  }

  static const AppColors fallbackDark = darkColors;
  static const AppColors fallbackLight = lightColors;
}

extension AppColorsExt on AppColors {
  Color get primary => goldPrimary;
  Color get foreground => textPrimary;
  Color get background => scaffoldBackground;
  Color get border => borderGlass;
  Color get live => emeraldLive;
}

extension AppThemeExtension on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppThemeService.darkColors
          : AppThemeService.lightColors);
  AppColors get cs => colors;
  ThemeData get theme => Theme.of(this);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  bool get isLight => Theme.of(this).brightness == Brightness.light;
}
