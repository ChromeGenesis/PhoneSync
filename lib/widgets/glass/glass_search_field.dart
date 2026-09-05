import 'dart:async';
import 'package:flutter/material.dart';
import '../shared/text_style_cache.dart';

import '../../services/theme_service.dart';
import 'glass_input.dart';

/// A reusable frosted-glass search field with debounce, clear button, and
/// optional loading indicator suffix.
///
/// Replaces the three copy-pasted `TextField + glassInputDecoration + suffix`
/// blocks in `songs_view.dart`, `scriptures_view.dart`, and
/// `media_alerts_deck.dart`.
///
/// Usage:
/// ```dart
/// GlassSearchField(
///   controller: _searchController,
///   hintText: 'Search songs & hymns...',
///   onChanged: _onSearchChanged,
/// )
/// ```
class GlassSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final FocusNode? focusNode;

  /// When true, shows a `CircularProgressIndicator` in the suffix slot instead
  /// of the clear button. Useful for async search (e.g. scriptures view).
  final bool isLoading;

  /// Extra text style overrides.
  final double fontSize;

  /// When true (default), focuses or taps on the search bar select all text.
  final bool selectAllOnFocus;

  const GlassSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.isLoading = false,
    this.fontSize = 13.0,
    this.selectAllOnFocus = true,
  });

  @override
  State<GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<GlassSearchField> {
  FocusNode? _internalFocusNode;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(GlassSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalFocusNode)?.removeListener(_handleFocusChange);
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_effectiveFocusNode.hasFocus && widget.selectAllOnFocus && widget.controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_effectiveFocusNode.hasFocus) return;
        widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.controller.text.length,
        );
      });
    }
  }

  void _selectAll() {
    if (widget.selectAllOnFocus && widget.controller.text.isNotEmpty) {
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget? suffix;
    if (widget.isLoading) {
      suffix = Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
        ),
      );
    } else if (widget.controller.text.isNotEmpty) {
      suffix = IconButton(
        icon: const Icon(Icons.close, size: 15),
        color: colors.textMuted,
        splashRadius: 14,
        onPressed: () {
          widget.controller.clear();
          widget.onChanged?.call('');
        },
      );
    }

    return TextField(
      controller: widget.controller,
      focusNode: _effectiveFocusNode,
      onTap: _selectAll,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted != null ? (_) => widget.onSubmitted!() : null,
      style: OutfitStyle.get(fontSize: widget.fontSize, color: colors.foreground),
      decoration: glassInputDecoration(
        context: context,
        hintText: widget.hintText,
        prefixIcon: Icon(Icons.search, size: 17, color: colors.primary),
        suffixIcon: suffix,
      ),
    );
  }
}

/// A debounced variant of [GlassSearchField] that handles the
/// `Timer`-debounce lifecycle internally.
///
/// Callers pass [onDebouncedChanged] and optionally [debounceMs].
/// The internal timer is cancelled on dispose — no extra work needed
/// in the parent state.
class DebouncedSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onDebouncedChanged;
  final VoidCallback? onSubmitted;
  final FocusNode? focusNode;
  final bool isLoading;
  final int debounceMs;
  final double fontSize;

  const DebouncedSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onDebouncedChanged,
    this.onSubmitted,
    this.focusNode,
    this.isLoading = false,
    this.debounceMs = 200,
    this.fontSize = 13.0,
  });

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  Timer? _timer;

  void _onChanged(String value) {
    _timer?.cancel();
    if (value.trim().isEmpty) {
      if (mounted) widget.onDebouncedChanged(value);
    } else {
      _timer = Timer(Duration(milliseconds: widget.debounceMs), () {
        if (mounted) widget.onDebouncedChanged(value);
      });
    }
    // Trigger rebuild so the clear button shows/hides immediately.
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassSearchField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      hintText: widget.hintText,
      onChanged: _onChanged,
      onSubmitted: widget.onSubmitted,
      isLoading: widget.isLoading,
      fontSize: widget.fontSize,
    );
  }
}
