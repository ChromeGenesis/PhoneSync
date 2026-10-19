import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import 'hover_builder.dart';

/// Reports whether a scrollable has content clipped below, without drawing
/// anything itself.
///
/// Kept separate from the indicator so the caller can position the indicator
/// *outside* a gradient/fade mask — a caret rendered inside the mask gets faded
/// into invisibility in exactly the region it is meant to occupy.
class ScrollOverflowWatcher extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController controller) builder;

  /// Fires only on transitions, not on every scroll frame.
  final ValueChanged<bool> onChanged;

  /// Supply your own controller when something outside this widget needs to
  /// drive the scroll — e.g. the caret strip that pages the list forward.
  /// Ownership stays with the caller; it is not disposed here.
  final ScrollController? controller;

  const ScrollOverflowWatcher({
    super.key,
    required this.builder,
    required this.onChanged,
    this.controller,
  });

  @override
  State<ScrollOverflowWatcher> createState() => _ScrollOverflowWatcherState();
}

class _ScrollOverflowWatcherState extends State<ScrollOverflowWatcher> {
  ScrollController? _internal;
  ScrollController get _controller =>
      widget.controller ?? (_internal ??= ScrollController());

  bool _hasMore = false;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // Viewport height can change (window resize, sidebar reflow) without any
    // scroll event firing, which can make clipped content suddenly fit.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _settle?.cancel();
    _controller.removeListener(_onScroll);
    _internal?.dispose();
    super.dispose();
  }

  void _onScroll() {
    _measure();
    // Re-measure once things settle: mid-fling, `pixels` is nowhere near the
    // final resting offset, so a single read flickers the indicator.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 120), _measure);
  }

  void _measure() {
    if (!mounted) return;
    if (!_controller.hasClients) {
      _emit(false);
      return;
    }
    final position = _controller.position;
    // 4px tolerance: sub-pixel layout rounding otherwise leaves the indicator
    // showing when the list is scrolled fully to the end.
    _emit(position.maxScrollExtent - position.pixels > 4);
  }

  void _emit(bool value) {
    if (value == _hasMore) return;
    _hasMore = value;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: widget.builder(context, _controller),
    );
  }
}

/// The animated "there is more below" affordance.
///
/// Occupies its own reserved strip rather than floating over the list, so it
/// can never sit on top of a row. Tapping it pages the list forward, which
/// makes it useful as well as decorative.
class ScrollCaretIndicator extends StatefulWidget {
  final ScrollController controller;

  /// Reserved height, so callers can pad their list by the same amount.
  static const double stripHeight = 20;

  const ScrollCaretIndicator({super.key, required this.controller});

  @override
  State<ScrollCaretIndicator> createState() => _ScrollCaretIndicatorState();
}

class _ScrollCaretIndicatorState extends State<ScrollCaretIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  void _pageDown() {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    final position = controller.position;
    controller.jumpTo(
      (position.pixels + position.viewportDimension * 0.8)
          .clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: ScrollCaretIndicator.stripHeight,
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          onTap: _pageDown,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: AnimatedBuilder(
              animation: _bob,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _bob.value * 2.5),
                child: child,
              ),
              child: Container(
                width: 34,
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: hovered
                      ? colors.goldPrimary.withAlpha(46)
                      : colors.goldPrimary.withAlpha(22),
                  border: Border.all(color: colors.goldPrimary.withAlpha(70)),
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: colors.goldPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}