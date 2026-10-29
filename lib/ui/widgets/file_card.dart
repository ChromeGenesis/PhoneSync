import 'package:flutter/material.dart';

import '../../core/adb/adb_models.dart';
import '../../core/thumbnails/thumbnail_service.dart';
import '../../services/theme_service.dart';
import '../../state/browser_controller.dart';
import '../../widgets/shared/hover_builder.dart';
import '../../widgets/shared/text_style_cache.dart';
import '../dialogs/file_actions.dart';
import '../dialogs/preview_dialog.dart';
import '../format.dart';

Color extColor(String ext) {
  const map = {
    'jpg': Color(0xFFF59E0B),
    'jpeg': Color(0xFFF59E0B),
    'png': Color(0xFF3B82F6),
    'gif': Color(0xFF8B5CF6),
    'webp': Color(0xFF14B8A6),
    'heic': Color(0xFFEC4899),
    'mp4': Color(0xFFEF4444),
    'mkv': Color(0xFFEF4444),
    'mov': Color(0xFFF97316),
    'pdf': Color(0xFFDC2626),
    'doc': Color(0xFF2563EB),
    'docx': Color(0xFF2563EB),
    'xls': Color(0xFF059669),
    'xlsx': Color(0xFF059669),
    'zip': Color(0xFFCA8A04),
    'apk': Color(0xFF22C55E),
    'mp3': Color(0xFFA855F7),
  };
  return map[ext] ?? const Color(0xFF94A3B8);
}

IconData iconFor(PhoneFile f) {
  if (f.isDir) return Icons.folder_rounded;
  if (f.isImage) return Icons.image_outlined;
  if (f.isVideo) return Icons.movie_outlined;
  switch (f.ext) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'zip':
    case 'rar':
    case '7z':
      return Icons.folder_zip_outlined;
    case 'apk':
      return Icons.android;
    case 'mp3':
    case 'wav':
    case 'flac':
      return Icons.music_note_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

class FileCard extends StatelessWidget {
  final PhoneFile file;

  const FileCard({super.key, required this.file});

  // Manual double-click tracking (shared across rebuilds — widget instances
  // are recreated constantly, so instance state would never see the 2nd tap).
  static String? _lastTapPath;
  static DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Registers the tap immediately instead of going through InkWell's
  /// onDoubleTap, which holds every single tap ~300ms to disambiguate.
  void _handleTap(BuildContext context, BrowserController browser) {
    final now = DateTime.now();
    // Only images were openable before, which left every folder in a listing
    // inert — the hierarchy was on screen but unreachable.
    final openable = file.isDir || file.isImage;
    final isDoubleTap =
        openable &&
        _lastTapPath == file.path &&
        now.difference(_lastTapAt) < const Duration(milliseconds: 300);
    _lastTapPath = file.path;
    _lastTapAt = now;
    if (isDoubleTap) {
      if (file.isDir) {
        // openLocation clears the selection, so there is nothing to cancel.
        browser.openPath(file.path);
        return;
      }
      browser.toggleSelect(file.path); // cancel the selection the 1st tap made
      showPreview(context, file);
      return;
    }
    browser.toggleSelect(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final browser = BrowserController.instance;
    return AnimatedBuilder(
      animation: browser,
      builder: (context, _) {
        final isSelected = browser.selection.contains(file.path);
        return HoverBuilder(
          builder: (context, hovered) {
            final bg = isSelected
                ? colors.goldPrimary.withAlpha(38)
                : hovered
                ? colors.surface.withAlpha(150)
                : colors.surface.withAlpha(90);
            final borderColor = isSelected
                ? colors.goldPrimary
                : hovered
                ? colors.border.withAlpha(70)
                : colors.border.withAlpha(30);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor,
                  width: isSelected ? 1.4 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _handleTap(context, browser),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        _thumb(colors),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OutfitStyle.get(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? colors.textGold
                                      : colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (file.ext.isNotEmpty) ...[
                                    _extBadge(colors),
                                    const SizedBox(width: 7),
                                  ],
                                  Text(
                                    '${file.size.formatBytes}  ·  ${file.modified.formatEpoch}',
                                    style: OutfitStyle.get(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // A folder's one explicit way in — the double-tap is
                        // otherwise invisible from the card itself.
                        if (file.isDir)
                          GlassLikeIconButton(
                            icon: Icons.folder_open_outlined,
                            tooltip: 'Open folder',
                            onTap: () => browser.openPath(file.path),
                          )
                        else if (file.isImage)
                          GlassLikeIconButton(
                            icon: Icons.visibility_outlined,
                            tooltip: 'Preview',
                            onTap: () => showPreview(context, file),
                          ),
                        // Quick actions (open / share / wallpaper / delete).
                        // Only on hover or when selected, so it never crowds
                        // the resting state of a long list.
                        AnimatedOpacity(
                          opacity: hovered || isSelected ? 1 : 0,
                          duration: const Duration(milliseconds: 130),
                          child: FileActionMenu(file: file),
                        ),
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 17,
                              height: 17,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colors.goldPrimary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isSelected
                                      ? colors.goldPrimary
                                      : colors.border.withAlpha(90),
                                  width: 1.4,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      size: 13,
                                      color: Colors.black,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _thumb(AppColors colors) {
    if (file.isDir) {
      return _iconBox(colors, Icons.folder_rounded, colors.goldPrimary);
    }
    final provider = ThumbnailService.instance.peek(file);
    if (provider != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(image: provider, width: 44, height: 44, fit: BoxFit.cover),
      );
    }
    return FutureBuilder<ImageProvider>(
      future: file.isImage ? ThumbnailService.instance.load(file) : null,
      builder: (context, snap) {
        final provider = snap.data;
        if (provider != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: provider,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          );
        }
        return _iconBox(colors, iconFor(file), extColor(file.ext));
      },
    );
  }

  Widget _iconBox(AppColors colors, IconData icon, Color tint) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.withAlpha(60)),
      ),
      child: Icon(icon, size: 21, color: tint),
    );
  }

  Widget _extBadge(AppColors colors) {
    final c = extColor(file.ext);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withAlpha(32),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        file.ext.toUpperCase(),
        style: OutfitStyle.get(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          color: c,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Small glass icon button used inside file rows (kept local to avoid
/// importing the button widget for a 28px ghost button).
class GlassLikeIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const GlassLikeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 16, color: colors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}
