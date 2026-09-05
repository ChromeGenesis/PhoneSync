import 'package:flutter/material.dart';
import 'text_style_cache.dart';

import '../../services/theme_service.dart';
import '../glass/glass_button.dart';

/// Standardized, reusable modal dialog shell for app modals.
///
/// Encapsulates:
/// - Frosted translucent backdrop container with ambient shadow
/// - Standardized header with icon pill, title, subtitle, and close button
/// - Optional scrollable/flexible body and action buttons footer
///
/// Ensures 100% consistent styling and zero boilerplate duplication across
/// `AlertEditorModal`, `CountdownEditorModal`, `LogoEditorModal`,
/// `NewSongModal`, `SettingsModal`, and sheet dialogs.
class GlassModalShell extends StatelessWidget {
  final Widget? icon;
  final String title;
  final String? subtitle;
  final Widget body;
  final double width;
  final double maxHeight;
  final EdgeInsetsGeometry padding;
  final List<Widget>? actions;
  final VoidCallback? onClose;
  final bool scrollable;

  const GlassModalShell({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.body,
    this.width = 580,
    this.maxHeight = 700,
    this.padding = const EdgeInsets.all(22),
    this.actions,
    this.onClose,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Header ────────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.goldPrimary.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.goldPrimary.withAlpha(90),
                        ),
                      ),
                      child: Center(child: icon),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: OutfitStyle.get(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(
                            subtitle!,
                            style: OutfitStyle.get(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white60
                                  : const Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: Icons.close,
              size: 30,
              iconSize: 16,
              onPressed: onClose ?? () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── 2. Body ──────────────────────────────────────────────────────────
        if (scrollable)
          Flexible(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(child: body),
            ),
          )
        else
          Flexible(child: body),

        // ── 3. Footer Actions (Optional) ─────────────────────────────────────
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: actions!),
        ],
      ],
    );

    final screenHeight = MediaQuery.sizeOf(context).height;
    final effectiveMaxHeight = (screenHeight - 88).clamp(300.0, maxHeight);

    return Center(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: width,
            constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
            padding: padding,
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(245),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.borderGlass, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
