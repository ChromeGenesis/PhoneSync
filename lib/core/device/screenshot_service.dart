import 'dart:io';

import '../../services/app_services.dart';
import '../adb/adb_client.dart';
import '../config/app_dirs.dart';
import '../log/log_service.dart';

/// A completed phone screenshot and what happened to it afterwards.
class ScreenshotCapture {
  final File file;
  final bool copiedToClipboard;

  const ScreenshotCapture({required this.file, required this.copiedToClipboard});
}

/// One-tap phone screenshots: `screencap -p` streamed over the device
/// transport into a timestamped PNG, plus a best-effort copy of the image to
/// the PC clipboard so the shot is immediately pasteable.
class ScreenshotService {
  ScreenshotService._();
  static final ScreenshotService instance = ScreenshotService._();

  static const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  /// Captures the connected phone's screen. Throws on failure with a
  /// human-readable message; the UI owns surfacing it.
  Future<ScreenshotCapture> capture() async {
    final dir = Directory(_dirPath);
    await dir.create(recursive: true);

    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final file = File('${dir.path}${Platform.pathSeparator}PhoneSync-$stamp.png');

    final total = await AdbClient.instance.screencapToFile(file);
    if (total < _pngMagic.length || !await _hasPngMagic(file)) {
      // screencap prints error text rather than failing the transport, so a
      // non-PNG payload must not be presented to the user as an image.
      try {
        await file.delete();
      } catch (_) {}
      throw StateError('the device did not return a screenshot');
    }

    final copied = Platform.isWindows && await copyImageToClipboard(file.path);
    Services.log.transfer(
        LogLevel.success, 'Screenshot saved — ${file.path} ($total bytes)');
    return ScreenshotCapture(file: file, copiedToClipboard: copied);
  }

  /// Copies an image file to the Windows clipboard (CF_BITMAP via WinForms).
  ///
  /// PowerShell needs -STA: the WinForms clipboard rejects calls from an MTA
  /// thread with "Current thread must be set to single thread apartment".
  /// Best-effort by design — a clipboard locked by another app just means the
  /// file is the deliverable.
  Future<bool> copyImageToClipboard(String path) async {
    if (!Platform.isWindows) return false;
    try {
      final escaped = path.replaceAll("'", "''");
      final script = 'Add-Type -AssemblyName System.Windows.Forms; '
          'Add-Type -AssemblyName System.Drawing; '
          "[System.Windows.Forms.Clipboard]::SetImage("
          "[System.Drawing.Image]::FromFile('$escaped'))";
      final res = await Process.run('powershell',
          ['-NoProfile', '-STA', '-Command', script]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Opens a local file with its default association.
  Future<void> openInDefaultApp(String path) async {
    if (Platform.isWindows) {
      Process.run('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else {
      Process.run('xdg-open', [path]);
    }
  }

  /// Screenshots live next to the pull destination, in their own folder, so
  /// they are discoverable without going through the app: Downloads/PhoneSync/Screenshots.
  String get _dirPath =>
      '${AppDirs.defaultSaveDir}${Platform.pathSeparator}PhoneSync'
      '${Platform.pathSeparator}Screenshots';

  Future<bool> _hasPngMagic(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(_pngMagic.length);
      for (var i = 0; i < _pngMagic.length; i++) {
        if (head[i] != _pngMagic[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }
}
