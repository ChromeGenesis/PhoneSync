import 'package:flutter/material.dart';
import 'text_style_cache.dart';

import '../../services/theme_service.dart';

/// Unified status pill used across live video, alert, logo, and photo decks.
///
/// Replaces the five independent inline badge Containers that were previously
/// copy-pasted across `logo_template_card`, `video_card_item`,
/// `media_photos_grid`, `live_monitor_video_preview`, and `monitor_active_deck`.
class LiveBadge extends StatelessWidget {
  /// The label text rendered inside the badge.
  final String label;

  /// Background color. Defaults to [AppColors.live] (green).
  final Color? color;

  /// Text / icon color. Defaults to [AppColors.liveBadgeText].
  final Color? textColor;

  /// When `true`, a small filled circle (dot indicator) is shown before the
  /// label — used for "ON AIR", "ALERT LIVE" etc.
  final bool showDot;

  /// Dot color. Defaults to [textColor].
  final Color? dotColor;

  /// Font size. Defaults to 8.
  final double fontSize;

  /// Custom padding. Defaults to horizontal 5, vertical 1.5.
  final EdgeInsetsGeometry? padding;

  /// Custom margin. Defaults to left 4.
  final EdgeInsetsGeometry? margin;

  /// Custom border radius. Defaults to 3.
  final double borderRadius;

  const LiveBadge({
    super.key,
    required this.label,
    this.color,
    this.textColor,
    this.showDot = false,
    this.dotColor,
    this.fontSize = 8.0,
    this.padding,
    this.margin = const EdgeInsets.only(left: 4),
    this.borderRadius = 3.0,
  });

  /// Convenience: green "LIVE" badge (default appearance).
  const LiveBadge.live({super.key})
    : label = 'LIVE',
      color = null,
      textColor = null,
      showDot = false,
      dotColor = null,
      fontSize = 8.0,
      padding = null,
      margin = const EdgeInsets.only(left: 4),
      borderRadius = 3.0;

  /// Convenience: gold "ARMED" badge for selected-but-not-live items.
  const LiveBadge.armed({super.key})
    : label = 'ARMED',
      color = null,
      textColor = null,
      showDot = false,
      dotColor = null,
      fontSize = 7.0,
      padding = null,
      margin = const EdgeInsets.only(left: 4),
      borderRadius = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = color ?? colors.live;
    final fg = textColor ?? colors.liveBadgeText;

    return Container(
      margin: margin,
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: showDot ? 5.0 : 5.0,
            vertical: 1.5,
          ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor ?? fg,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: OutfitStyle.get(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// "ARMED" badge variant: gold border, transparent bg — for selected-but-not-live.
class ArmedBadge extends StatelessWidget {
  const ArmedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.goldPrimary.withAlpha(50),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: colors.goldPrimary.withAlpha(160), width: 0.8),
      ),
      child: Text(
        'ARMED',
        style: OutfitStyle.get(
          fontSize: 7,
          fontWeight: FontWeight.w900,
          color: colors.textGold,
        ),
      ),
    );
  }
}
