import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adb/adb_client.dart';
import '../../core/adb/adb_models.dart';
import '../../services/theme_service.dart';
import '../../widgets/shared/text_style_cache.dart';
import '../format.dart';

/// Fullscreen image preview: streams the file over `exec-out`, then shows it
/// in an InteractiveViewer with Fit / 1:1 controls.
Future<void> showPreview(BuildContext context, PhoneFile file) async {
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withAlpha(235),
      pageBuilder: (context, _, _) => _PreviewOverlay(file: file),
      transitionsBuilder: (context, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
}

class _PreviewOverlay extends StatefulWidget {
  final PhoneFile file;
  const _PreviewOverlay({required this.file});

  @override
  State<_PreviewOverlay> createState() => _PreviewOverlayState();
}

class _PreviewOverlayState extends State<_PreviewOverlay> {
  final _controller = TransformationController();
  Uint8List? _bytes;
  String? _error;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await AdbClient.instance.catBytes(widget.file.path);
      if (mounted) setState(() => _bytes = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _fit() => _controller.value = Matrix4.identity();
  void _fullScale() {
    final size = MediaQuery.sizeOf(context);
    _controller.value = Matrix4.identity()
      ..translateByDouble(-size.width * 0.25, -size.height * 0.25, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
  }

  /// Zoom keeping the viewport center anchored (keyboard: + / = / -).
  void _zoomBy(double factor) {
    final current = _controller.value.getMaxScaleOnAxis();
    final applied = (current * factor).clamp(0.5, 8.0) / current;
    final size = MediaQuery.sizeOf(context);
    _controller.value = Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..multiply(_controller.value)
      ..scaleByDouble(applied, applied, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  /// Ported from PhoneSync_Old preview.py: Esc closes, +/= zoom in,
  /// - zooms out, 0 resets to fit.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.equal) {
      _zoomBy(1.25);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(1 / 1.25);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _fit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final current = _controller.value.getMaxScaleOnAxis();
    if (current > 1.5) {
      _fit();
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    const scale = 2.5;
    if (position != null) {
      _controller.value = Matrix4.identity()
        ..translateByDouble(
          -position.dx * (scale - 1),
          -position.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onDoubleTapDown: _handleDoubleTapDown,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 0.5,
                  maxScale: 8,
                  panEnabled: true,
                  child: Center(child: _image(context)),
                ),
              ),
            ),
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withAlpha(180), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: colors.textGold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OutfitStyle.get(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.file.size.formatBytes}  ·  ${widget.file.modified.formatEpoch}',
                      style: OutfitStyle.get(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _pillButton(context, 'Fit', _fit),
                    const SizedBox(width: 6),
                    _pillButton(context, '1:1', _fullScale),
                    const SizedBox(width: 6),
                    _pillButton(
                      context,
                      'Close',
                      () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton(BuildContext context, String label, VoidCallback onTap) {
    final colors = context.colors;
    return Material(
      color: colors.surface.withAlpha(150),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border.withAlpha(60)),
          ),
          child: Text(
            label,
            style: OutfitStyle.get(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final colors = context.colors;
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 42, color: colors.roseDanger),
          const SizedBox(height: 10),
          Text(
            'Preview failed to load',
            style: OutfitStyle.get(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: OutfitStyle.get(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
        ],
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 12),
          Text(
            'Streaming over ADB…',
            style: OutfitStyle.get(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
        ],
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, err, stack) =>
          Icon(Icons.broken_image_outlined, size: 42, color: colors.roseDanger),
    );
  }
}
