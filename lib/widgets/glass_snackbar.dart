import 'package:flutter/material.dart';

import '../services/theme_service.dart';
import 'shared/text_style_cache.dart';

enum SnackType { success, error, warning, info }

/// Premium overlay snackbar with a pulsing glow icon, slide-in animation, and
/// a countdown progress bar. Variants: success / error / warning / info.
/// Ported from the trademum design system and adapted to AppColors.
class GlassSnackbar {
  GlassSnackbar._();

  static final Map<String, bool> _activeSnacks = {};

  static void show(
    BuildContext context, {
    required SnackType type,
    required String title,
    required String message,
    Duration duration = const Duration(milliseconds: 2500),
    VoidCallback? onTap,
  }) {
    if (!context.mounted) return;

    // Deduplicate identical snacks so they can't stack on top of each other.
    final key = '$title$message';
    if (_activeSnacks[key] ?? false) return;
    _activeSnacks[key] = true;

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GlassSnackbarWidget(
        type: type,
        title: title,
        message: message,
        duration: duration,
        onDismiss: () {
          _activeSnacks.remove(key);
          if (entry.mounted) {
            entry.remove();
          }
        },
        onTap: onTap,
      ),
    );
    overlay.insert(entry);
  }
}

class _GlassSnackbarWidget extends StatefulWidget {
  const _GlassSnackbarWidget({
    required this.type,
    required this.title,
    required this.message,
    required this.duration,
    required this.onDismiss,
    this.onTap,
  });

  final SnackType type;
  final String title;
  final String message;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  @override
  State<_GlassSnackbarWidget> createState() => _GlassSnackbarWidgetState();
}

class _GlassSnackbarWidgetState extends State<_GlassSnackbarWidget>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  late final AnimationController _progressCtrl;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutExpo));

    _progressCtrl = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _dismiss();
      });

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.22,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _glowAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _slideCtrl.forward().then((_) => _progressCtrl.forward());
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _progressCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _dismiss() async {
    _pulseCtrl.stop();
    _progressCtrl.stop();
    if (mounted) {
      await _slideCtrl.animateBack(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInCubic,
      );
    }
    widget.onDismiss();
  }

  IconData get _icon {
    switch (widget.type) {
      case SnackType.success:
        return Icons.check_circle_outline_rounded;
      case SnackType.error:
        return Icons.error_outline_rounded;
      case SnackType.warning:
        return Icons.warning_amber_rounded;
      case SnackType.info:
        return Icons.info_outline_rounded;
    }
  }

  Color _accent(AppColors colors) {
    switch (widget.type) {
      case SnackType.success:
        return colors.emeraldLive;
      case SnackType.error:
        return colors.roseDanger;
      case SnackType.warning:
        return colors.goldPrimary;
      case SnackType.info:
        return const Color(0xFF378ADD);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = colors.surface;
    final fg = colors.textPrimary;
    final topPad = MediaQuery.paddingOf(context).top;

    // Desktop layout: centered pill with a capped width instead of the
    // mobile full-width bar.
    return Positioned(
      top: topPad + 10,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnim,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: GestureDetector(
              onTap: widget.onTap,
              onVerticalDragEnd: (details) {
                if (details.velocity.pixelsPerSecond.dy < 0) {
                  _dismiss();
                }
              },
              onHorizontalDragEnd: (_) => _dismiss(),
              child: _buildCard(colors, bg, fg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(AppColors colors, Color bg, Color fg) {
    final accent = _accent(colors);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: bg.withAlpha(240),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: fg.withAlpha(35)),
        ),
        // Clip the progress bar (and anything else) to the card's rounded
        // corners so the bottom track doesn't poke past them.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RepaintBoundary(
                      child: _PulsingIcon(
                        icon: _icon,
                        accent: accent,
                        scaleAnim: _scaleAnim,
                        glowAnim: _glowAnim,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: OutfitStyle.get(
                              color: fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.message,
                            style: OutfitStyle.get(
                              color: fg,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _dismiss,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: fg.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: fg.withAlpha(25)),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: fg.withAlpha(200),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _progressCtrl,
                  builder: (_, _) {
                    return Container(
                      height: 3,
                      color: fg.withAlpha(15),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1.0 - _progressCtrl.value,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent.withAlpha(200),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatelessWidget {
  const _PulsingIcon({
    required this.icon,
    required this.accent,
    required this.scaleAnim,
    required this.glowAnim,
  });

  final IconData icon;
  final Color accent;
  final Animation<double> scaleAnim;
  final Animation<double> glowAnim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scaleAnim,
      builder: (_, _) {
        final glowAlpha = (glowAnim.value * 217).round();
        final glowRadius = glowAnim.value * 8.0;

        return Transform.scale(
          scale: scaleAnim.value,
          child: Icon(
            icon,
            size: 24,
            color: accent,
            shadows: [
              Shadow(
                color: accent.withAlpha(glowAlpha),
                blurRadius: glowRadius,
              ),
            ],
          ),
        );
      },
    );
  }
}
