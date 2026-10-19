import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../../widgets/shared/text_style_cache.dart';
import '../views/settings_view.dart';

/// Settings live in a large glassmorphic modal instead of a full-screen tab —
/// Esc, the ✕, or clicking the scrim all return you to whatever you were doing.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withAlpha(130),
    builder: (context) => const SettingsDialog(),
  );
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: 980,
            height: 660,
            decoration: BoxDecoration(
              color: colors.scaffoldBackground.withAlpha(242),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.border.withAlpha(70)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(90),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: colors.goldPrimary.withAlpha(30),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: colors.goldPrimary,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Text(
                        'Settings',
                        style: OutfitStyle.get(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Surface the shortcut in the one place it is relevant.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface.withAlpha(90),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: colors.border.withAlpha(50),
                          ),
                        ),
                        child: Text(
                          // ⌘ exists only on macOS; every other desktop target
                          // uses Ctrl, so the hint follows the platform rather
                          // than assuming the author's Mac.
                          switch (defaultTargetPlatform) {
                            TargetPlatform.macOS => '⌘S',
                            _ => 'Ctrl+S',
                          },
                          style: FiraCodeStyle.get(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _closeButton(context),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.border.withAlpha(45)),
                const Expanded(child: SettingsView()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _closeButton(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.close_rounded, size: 18, color: colors.textSecondary),
      ),
    );
  }
}
