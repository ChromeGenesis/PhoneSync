import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import 'text_style_cache.dart';

/// Dark / Light / System segmented control. Lives in the header (always one
/// click away) and is reused in Settings — one widget, one source of truth
/// (AppThemeService).
class ThemeModeSelector extends StatelessWidget {
  final bool compact;

  const ThemeModeSelector({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = AppThemeService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.surface.withAlpha(110),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border.withAlpha(50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (mode, icon, label) in const [
                (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
                (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
                (ThemeMode.system, Icons.settings_suggest_outlined, 'System'),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: GestureDetector(
                    onTap: () => service.setThemeMode(mode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.symmetric(
                          horizontal: compact ? 9 : 12, vertical: compact ? 5 : 6),
                      decoration: BoxDecoration(
                        color: service.themeMode == mode
                            ? colors.goldPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon,
                              size: compact ? 13 : 14,
                              color: service.themeMode == mode
                                  ? Colors.black
                                  : colors.textSecondary),
                          if (!compact) ...[
                            const SizedBox(width: 5),
                            Text(
                              label,
                              style: OutfitStyle.get(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: service.themeMode == mode
                                      ? Colors.black
                                      : colors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
