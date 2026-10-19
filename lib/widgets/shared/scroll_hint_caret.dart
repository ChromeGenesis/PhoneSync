import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

/// Wraps a scrollable in an animated overflow caret.
///
/// A gradient fade on its own is easy to miss on a short list — it just reads
/// as a slightly soft bottom edge. A small bobbing arrow states plainly that
/// there is more below, then gets out of the way the moment the remaining
/// content fits, so it never becomes noise.
///
/// The scrollable is supplied through [builder] rather than as a `child` so
/// this can own the [ScrollController] and hand it in — the controller is what
/// makes "is there more?" answerable at all.
class ScrollHintCaret extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController controller) builder;

  final bool enabled;
  final EdgeInsets padding;

  const ScrollHintCaret({
    super.key,
    required this.builder,
    this.enabled = true,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<ScrollHintCaret> createState() => _ScrollHintCaretState();
}

class _ScrollHintCaretState extends State<ScrollHintCaret>
    with SingleTickerProviderStateMixin {
  final _controller = ScrollController();

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  bool _hasMore = false;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // Viewport height can change (window resize, sidebar reflow), which can make
    // previously-clipped content fit without any scroll event firing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _settle?.cancel();
    _bob.dispose();
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    _measure();
    // Measure again once things settle: mid-fling, `pixels` is nowhere near the
    // final resting place, so a single read makes the caret flicker.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 120), _measure);
  }

  void _measure() {
    if (!mounted) return;
    if (!_controller.hasClients) {
      if (_hasMore) setState(() => _hasMore = false);
      return;
    }
    final position = _controller.position;
    // 4px of tolerance: sub-pixel layout rounding otherwise leaves the caret
    // visible when the list is scrolled fully to the end.
    final more = position.maxScrollExtent - position.pixels > 4;
    if (more != _hasMore) setState(() => _hasMore = more);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: widget.padding,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
              return false;
            },
            child: widget.builder(context, _controller),
          ),
        ),
        if (widget.enabled)
          Positioned(
            left: 0,
            right: 0,
            bottom: 2,
            child: Center(
              child: IgnorePointer(
                // Purely informational — must never swallow a tap meant for
                // the list underneath.
                child: AnimatedOpacity(
                  opacity: _hasMore ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: AnimatedBuilder(
                    animation: _bob,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, _bob.value * 3.5),
                      child: child,
                    ),
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.colors.surface.withAlpha(210),
                        border: Border.all(
                            color: context.colors.goldPrimary.withAlpha(90)),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.goldGlow,
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: context.colors.goldPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}