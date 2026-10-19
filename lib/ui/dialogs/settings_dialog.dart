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

    // Size to the window instead of hard-coding 980x660. A fixed box taller
    // than the viewport overflows, and Dialog centres the overflow — which
    // clips the top and bottom of the content symmetrically and reads as
    // "vertically centred". A fixed *width* on a narrow window squeezes the
    // rail and panel until labels wrap mid-word.
    // 820 is what the content actually wants: a 220px rail, 48px of panel
    // padding, and a 520px-wide control (the destination picker) leave ~30px
    // spare. Anything wider is dead space.
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 72).clamp(360.0, 820.0).toDouble();
    final height = (screen.height - 72).clamp(380.0, 700.0).toDouble();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: width,
            height: height,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'PhoneSync Settings',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OutfitStyle.get(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              'Connection, transfers, storage & appearance',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OutfitStyle.get(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
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
                // The view owns its own search field, footer and dividers; the
                // dialog contributes only the title bar.
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
