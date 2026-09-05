import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/theme_service.dart';
import '../shared/text_style_cache.dart';

/// Gap between the select field and its dropdown menu.
const double _kMenuGap = 4.0;

/// Glass segmented selector for Theme Switcher (Dark / Light / System) & multi-choice toggles.
class GlassSegmentedControl<T> extends StatelessWidget {
  final T selectedValue;
  final Map<T, Widget> children;
  final ValueChanged<T> onValueChanged;

  const GlassSegmentedControl({
    super.key,
    required this.selectedValue,
    required this.children,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(
          color: colors.borderSubtle,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children.entries.map((entry) {
          final isSelected = entry.key == selectedValue;
          return GestureDetector(
            onTap: () => onValueChanged(entry.key),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7.0),
              clipBehavior: Clip.antiAlias,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? colors.goldPrimary : colors.textGold)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7.0),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: colors.goldGlow,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: IconTheme(
                  data: IconThemeData(
                    color: isSelected
                        ? colors.scaffoldBackground
                        : colors.textSecondary,
                    size: 15,
                  ),
                  child: DefaultTextStyle(
                    style: OutfitStyle.get(
                      color: isSelected
                          ? colors.scaffoldBackground
                          : colors.textSecondary,
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                    ),
                    child: entry.value,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Custom sleek glass selector dropdown to eliminate standard Material dropdowns.
class GlassSelect<T> extends StatefulWidget {
  final T value;
  final List<GlassSelectItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? label;
  final Widget? prefixIcon;
  final double? menuWidth;
  final double? menuMaxHeight;

  const GlassSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.prefixIcon,
    this.menuWidth,
    this.menuMaxHeight,
  });

  @override
  State<GlassSelect<T>> createState() => GlassSelectState<T>();
}

class GlassSelectState<T> extends State<GlassSelect<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  // Drives highlight navigation when the dropdown is already open.
  // Signalled by selectNextItem (+1) / selectPrevItem (-1).
  ValueNotifier<int>? _overlayNotifier;

  bool get isOpen => _overlayEntry != null;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _removeOverlay();
    }
  }

  void openDropdown({
    int? initialIndex,
    bool selectNext = false,
    bool selectPrev = false,
  }) {
    if (isOpen) {
      if (selectNext) {
        selectNextItem();
      } else if (selectPrev) {
        selectPrevItem();
      }
      return;
    }

    final currentIndex = widget.items.indexWhere((it) => it.value == widget.value);
    int startIndex = initialIndex ?? (currentIndex != -1 ? currentIndex : 0);
    if (selectNext && widget.items.isNotEmpty) {
      startIndex = (startIndex + 1) % widget.items.length;
    } else if (selectPrev && widget.items.isNotEmpty) {
      startIndex = (startIndex - 1 + widget.items.length) % widget.items.length;
    }

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    // Fit the menu to the window viewport: flip upward when there is more room
    // above the field than below, and clamp the height so it never renders
    // past the window edge.
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final overlayHeight = overlayBox?.size.height ?? 0;
    final targetTop = renderBox.localToGlobal(Offset.zero).dy;
    final spaceBelow = overlayHeight - targetTop - size.height - _kMenuGap;
    final spaceAbove = targetTop - _kMenuGap;
    final hasSubtitles = widget.items.any((it) => it.subtitle != null);
    final estimatedItemHeight = hasSubtitles ? 46.0 : 36.0;
    final desiredHeight = math.min(
      widget.menuMaxHeight ?? 280,
      widget.items.isEmpty
          ? 0.0
          : widget.items.length * estimatedItemHeight + 10,
    );
    final openUpward = spaceBelow < desiredHeight && spaceAbove > spaceBelow;
    final available = math.max(120.0, openUpward ? spaceAbove : spaceBelow);
    final effectiveMaxHeight = math.min(widget.menuMaxHeight ?? 280, available);

    _overlayNotifier = ValueNotifier<int>(0);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _GlassSelectDropdownOverlay<T>(
        layerLink: _layerLink,
        targetSize: size,
        items: widget.items,
        selectedValue: widget.value,
        initialIndex: startIndex,
        customWidth: widget.menuWidth,
        maxHeight: effectiveMaxHeight,
        openUpward: openUpward,
        notifier: _overlayNotifier!,
        onSelect: (val) {
          _removeOverlay();
          widget.onChanged(val);
        },
        onDismiss: _removeOverlay,
      ),
    );

    overlay.insert(_overlayEntry!);
    if (mounted) setState(() {});
  }

  void closeDropdown() {
    _removeOverlay();
  }

  void selectNextItem() {
    _overlayNotifier?.value = (_overlayNotifier?.value ?? 0) + 1;
  }

  void selectPrevItem() {
    _overlayNotifier?.value = (_overlayNotifier?.value ?? 0) - 1;
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry?.dispose();
      _overlayEntry = null;
      _overlayNotifier?.dispose();
      _overlayNotifier = null;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedItem = widget.items.firstWhere(
      (it) => it.value == widget.value,
      orElse: () => widget.items.first,
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label != null) ...[
            Text(
              widget.label!,
              style: OutfitStyle.get(
                color: colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
          ],
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                if (isOpen) {
                  closeDropdown();
                } else {
                  openDropdown();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: colors.inputBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isOpen ? colors.goldPrimary : colors.inputBorder,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.prefixIcon != null) ...[
                            widget.prefixIcon!,
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              selectedItem.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OutfitStyle.get(
                                fontSize: 12,
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.unfold_more_rounded,
                      size: 16,
                      color: isOpen ? colors.goldPrimary : colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassSelectDropdownOverlay<T> extends StatefulWidget {
  final LayerLink layerLink;
  final Size targetSize;
  final List<GlassSelectItem<T>> items;
  final T selectedValue;
  final int initialIndex;
  final double? customWidth;
  final double maxHeight;
  final bool openUpward;
  final ValueNotifier<int> notifier;
  final ValueChanged<T> onSelect;
  final VoidCallback onDismiss;

  const _GlassSelectDropdownOverlay({
    required this.layerLink,
    required this.targetSize,
    required this.items,
    required this.selectedValue,
    required this.initialIndex,
    required this.customWidth,
    required this.maxHeight,
    required this.openUpward,
    required this.notifier,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_GlassSelectDropdownOverlay<T>> createState() =>
      _GlassSelectDropdownOverlayState<T>();
}

class _GlassSelectDropdownOverlayState<T>
    extends State<_GlassSelectDropdownOverlay<T>> {
  late int _highlightedIndex;
  // Tracks the last notifier value so we can determine direction on each tick.
  late int _lastNotifierValue;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _highlightedIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _lastNotifierValue = widget.notifier.value;
    widget.notifier.addListener(_onNotifierChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _scrollToIndex(_highlightedIndex, animate: false);
      }
    });
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNotifierChanged() {
    final newValue = widget.notifier.value;
    if (newValue > _lastNotifierValue) {
      _highlightNext();
    } else if (newValue < _lastNotifierValue) {
      _highlightPrev();
    }
    _lastNotifierValue = newValue;
  }

  void _scrollToIndex(int index, {bool animate = true}) {
    if (!_scrollController.hasClients || widget.items.isEmpty) return;
    final hasSubtitles = widget.items.any((it) => it.subtitle != null);
    final itemHeight = hasSubtitles ? 44.0 : 34.0;
    final targetOffset = (index * itemHeight) - (widget.maxHeight / 2) + (itemHeight / 2);
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (animate) {
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(clampedOffset);
    }
  }

  void _highlightNext() {
    if (widget.items.isEmpty) return;
    setState(() {
      _highlightedIndex = (_highlightedIndex + 1) % widget.items.length;
    });
    _scrollToIndex(_highlightedIndex);
  }

  void _highlightPrev() {
    if (widget.items.isEmpty) return;
    setState(() {
      _highlightedIndex =
          (_highlightedIndex - 1 + widget.items.length) % widget.items.length;
    });
    _scrollToIndex(_highlightedIndex);
  }

  void _confirmSelection() {
    if (widget.items.isEmpty) {
      widget.onDismiss();
      return;
    }
    final selected = widget.items[_highlightedIndex].value;
    widget.onSelect(selected);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _highlightNext();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _highlightPrev();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _confirmSelection();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final hasSubtitles = widget.items.any((it) => it.subtitle != null);
    final minW = hasSubtitles ? 210.0 : widget.targetSize.width;
    final effectiveWidth = widget.customWidth ?? minW.clamp(widget.targetSize.width, 320.0);

    return Stack(
      children: [
        // Outside dismiss tap catcher
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        // Dropdown menu anchored to target
        Positioned(
          width: effectiveWidth,
          child: CompositedTransformFollower(
            link: widget.layerLink,
            showWhenUnlinked: false,
            targetAnchor: widget.openUpward ? Alignment.topLeft : Alignment.bottomLeft,
            followerAnchor:
                widget.openUpward ? Alignment.bottomLeft : Alignment.topLeft,
            offset: Offset(0, widget.openUpward ? -_kMenuGap : _kMenuGap),
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.borderGlass,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 160 : 35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: colors.goldGlow.withAlpha(isDark ? 20 : 10),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
                        itemCount: widget.items.length,
                        itemBuilder: (ctx, i) {
                          final item = widget.items[i];
                          final isCurrent = item.value == widget.selectedValue;
                          final isHighlighted = i == _highlightedIndex;

                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) {
                              if (_highlightedIndex != i) {
                                setState(() => _highlightedIndex = i);
                              }
                            },
                            child: GestureDetector(
                              onTap: () => widget.onSelect(item.value),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: item.subtitle != null ? 6 : 7,
                                ),
                                decoration: BoxDecoration(
                                  color: isHighlighted
                                      ? colors.goldPrimary.withAlpha(isDark ? 36 : 28)
                                      : (isCurrent
                                          ? colors.surfaceVariant.withAlpha(isDark ? 30 : 60)
                                          : Colors.transparent),
                                  borderRadius: BorderRadius.circular(8),
                                  border: isHighlighted
                                      ? Border.all(
                                          color: colors.goldPrimary.withAlpha(isDark ? 90 : 70),
                                          width: 1.0,
                                        )
                                      : Border.all(
                                          color: Colors.transparent,
                                          width: 1.0,
                                        ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  item.label,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: OutfitStyle.get(
                                                    fontSize: 12.5,
                                                    color: isHighlighted
                                                        ? colors.textGold
                                                        : colors.textPrimary,
                                                    fontWeight: (isCurrent || isHighlighted)
                                                        ? FontWeight.w700
                                                        : FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (item.badge != null) ...[
                                                const SizedBox(width: 7),
                                                Builder(
                                                  builder: (context) {
                                                    final isOffline =
                                                        item.badge == 'Offline';
                                                    return Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1.5,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isOffline
                                                            ? colors.emeraldLive.withAlpha(isDark ? 35 : 25)
                                                            : colors.borderSubtle,
                                                        borderRadius:
                                                            BorderRadius.circular(4),
                                                        border: Border.all(
                                                          color: isOffline
                                                              ? colors.emeraldLive.withAlpha(isDark ? 90 : 70)
                                                              : colors.borderGlass,
                                                          width: 0.8,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        item.badge!,
                                                        style: OutfitStyle.get(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.w700,
                                                          color: isOffline
                                                              ? colors.emeraldLive
                                                              : colors.textSecondary,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (item.subtitle != null) ...[
                                            const SizedBox(height: 1.5),
                                            Text(
                                              item.subtitle!,
                                              style: OutfitStyle.get(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                                color: isHighlighted
                                                    ? colors.textPrimary
                                                    : colors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isCurrent)
                                      Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: colors.goldPrimary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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

class GlassSelectItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final String? badge;

  const GlassSelectItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.badge,
  });
}
