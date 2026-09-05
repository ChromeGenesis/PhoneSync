import 'package:flutter/material.dart';

/// Declarative hover-state wrapper.
///
/// Replaces the 8+ `StatefulWidget` subclasses whose sole purpose was
/// tracking `bool _isHovered` via `MouseRegion.onEnter/onExit` + `setState`.
///
/// Before (boilerplate):
/// ```dart
/// class _FooState extends State<Foo> {
///   bool _isHovered = false;
///   Widget build(BuildContext context) {
///     return MouseRegion(
///       onEnter: (_) => setState(() => _isHovered = true),
///       onExit:  (_) => setState(() => _isHovered = false),
///       child: _isHovered ? widgetA : widgetB,
///     );
///   }
/// }
/// ```
///
/// After:
/// ```dart
/// HoverBuilder(
///   builder: (context, isHovered) => isHovered ? widgetA : widgetB,
/// )
/// ```
class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;
  final MouseCursor cursor;

  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.builder(context, _isHovered),
    );
  }
}
