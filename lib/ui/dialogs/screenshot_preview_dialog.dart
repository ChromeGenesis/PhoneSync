import 'dart:io';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/log/log_service.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../widgets/glass/glass_button.dart';
import '../../widgets/glass_snackbar.dart';
import '../../widgets/shared/glass_modal_shell.dart';
import '../../widgets/shared/text_style_cache.dart';
import '../../state/connection_controller.dart';

/// One tap anywhere in the UI: capture the phone's screen, save it under
/// Downloads/PhoneSync/Screenshots, copy it to the PC clipboard, and confirm.
/// Tapping the confirmation opens the preview.
Future<void> takePhoneScreenshot(BuildContext context) async {
  if (!ConnectionController.instance.isConnected) {
    showAppSnack(
      context,
      type: SnackType.error,
      title: 'No device connected',
      message: 'Connect the phone before taking a screenshot.',
    );
    return;
  }
  try {
    final capture = await Services.screenshots.capture();
    if (!context.mounted) return;
    final name = capture.file.uri.pathSegments.last;
    showAppSnack(
      context,
      type: SnackType.success,
      title: 'Screenshot saved${capture.copiedToClipboard ? ' — on your clipboard' : ''}',
      message: name,
      duration: const Duration(milliseconds: 3800),
      onTap: () => showScreenshotPreview(context, capture.file),
    );
  } catch (e) {
    Services.log.transfer(LogLevel.error, 'Screenshot failed — $e');
    if (!context.mounted) return;
    showAppSnack(
      context,
      type: SnackType.error,
      title: 'Screenshot failed',
      message: '$e',
    );
  }
}

/// Full-size view of a captured screenshot with the follow-up actions.
Future<void> showScreenshotPreview(BuildContext context, File file) {
  return showDialog(
    context: context,
    builder: (_) => _ScreenshotPreviewDialog(file: file),
  );
}

class _ScreenshotPreviewDialog extends StatelessWidget {
  final File file;

  const _ScreenshotPreviewDialog({required this.file});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = file.uri.pathSegments.last;
    return GlassModalShell(
      icon: Icon(Icons.photo_camera_rounded, size: 17, color: colors.goldPrimary),
      title: 'Phone Screenshot',
      subtitle: name,
      width: 640,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.48,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(file, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 13, color: colors.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  file.path,
                  style: FiraCodeStyle.get(
                      fontSize: 10, fontWeight: FontWeight.w500, color: colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Reveal Folder',
          icon: const Icon(Icons.folder_open_rounded, size: 15),
          onPressed: () => Services.screenshots.openInDefaultApp(file.parent.path),
        ),
        const SizedBox(width: 8),
        GlassButton(
          label: 'Copy to Clipboard',
          icon: const Icon(Icons.copy_rounded, size: 15),
          onPressed: () async {
            final ok = await Services.screenshots.copyImageToClipboard(file.path);
            if (!context.mounted) return;
            showAppSnack(
              context,
              type: ok ? SnackType.success : SnackType.error,
              title: ok ? 'Image copied' : 'Clipboard busy',
              message: ok ? 'Paste it anywhere.' : 'Another app is holding the clipboard.',
            );
          },
        ),
        const SizedBox(width: 8),
        GlassButton(
          label: 'Open',
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          isPrimary: true,
          onPressed: () => Services.screenshots.openInDefaultApp(file.path),
        ),
      ],
    );
  }
}
