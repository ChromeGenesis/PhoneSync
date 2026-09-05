import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// Lightweight, high-performance ambient sanctuary background.
/// Uses layered radial gradient orbs behind translucent containers to achieve
/// stunning visual glass depth with ZERO expensive [BackdropFilter] or CPU/GPU blur overhead.
class SanctuaryBackground extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;

  const SanctuaryBackground({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      color: backgroundColor ?? colors.scaffoldBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Top-left Amber/Gold Ambient Glow Orb — displaced from the
          // exact corner so the bleed looks natural.
          Positioned(
            top: -90,
            left: -70,
            child: IgnorePointer(
              child: Container(
                width: 480,
                height: 480,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      isDark
                          ? colors.goldPrimary.withAlpha(60)
                          : colors.goldPrimary.withAlpha(30),
                      colors.goldPrimary.withAlpha(0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 2. Bottom-right Indigo/Sapphire Ambient Glow Orb — displaced
          // from the exact corner.
          Positioned(
            bottom: -60,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 440,
                height: 440,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      isDark
                          ? colors.orbSecondary.withAlpha(70)
                          : colors.orbSecondary.withAlpha(35),
                      colors.orbSecondary.withAlpha(0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 4. Foreground Interactive UI
          child,
        ],
      ),
    );
  }
}
