import '../adb/adb_client.dart';
import '../adb/adb_models.dart';
import '../log/log_service.dart';
import '../../state/browser_controller.dart';
import '../../state/connection_controller.dart';
import '../../services/app_services.dart';

/// Device-side operations that mutate or hand off a file, wrapped so every
/// caller gets the same logging, cache invalidation and failure reporting.
///
/// Without this the logic scatters into widget callbacks, where it is easy to
/// fire a destructive intent, forget to log it, and serve a stale listing
/// afterwards.
class DeviceActions {
  DeviceActions._();
  static final DeviceActions instance = DeviceActions._();

  static bool get _ready => ConnectionController.instance.isConnected;

  /// Opens a file in whichever app on the phone claims its type.
  Future<bool> open(PhoneFile file) async {
    if (!_ready) return false;
    final ok = await AdbClient.instance.openFileOnDevice(file.path);
    _report(ok, 'Opened ${file.name} on device',
        'Could not open ${file.name} — no app claims that type');
    return ok;
  }

  /// Opens the system share sheet for a file.
  Future<bool> share(PhoneFile file) async {
    if (!_ready) return false;
    final ok = await AdbClient.instance.shareFile(file.path);
    _report(ok, 'Shared ${file.name}', 'Share failed for ${file.name}');
    return ok;
  }

  /// Sets an image as the home-screen wallpaper.
  Future<bool> setWallpaper(PhoneFile file) async {
    if (!_ready) return false;
    if (!file.isImage) {
      Services.log.connection(
          LogLevel.warning, 'Cannot set ${file.name} as wallpaper — not an image');
      return false;
    }
    final ok = await AdbClient.instance.setWallpaper(file.path);
    _report(ok, 'Set ${file.name} as wallpaper',
        'Could not set wallpaper from ${file.name}');
    return ok;
  }

  /// Deletes files from the device.
  ///
  /// Returns how many were actually removed. Deliberately does NOT prompt —
  /// callers must confirm first, because this is irreversible and there is no
  /// undo and no trash can on most Android volumes.
  Future<int> delete(List<PhoneFile> files) async {
    if (!_ready || files.isEmpty) return 0;
    var removed = 0;
    for (final f in files) {
      final ok = await AdbClient.instance.deletePath(f.path);
      if (ok) {
        removed++;
        // A listing cached for the parent folder still lists a file that is
        // gone; drop it so the next visit re-lists instead of showing it.
        BrowserController.instance.invalidatePath(_parentOf(f.path));
      } else {
        Services.log.connection(LogLevel.error, 'Delete failed: ${f.path}');
      }
    }
    if (removed > 0) {
      Services.log.connection(
        LogLevel.warning,
        'Deleted $removed file(s) from device: ${files.take(3).map((f) => f.name).join(', ')}'
            '${files.length > 3 ? '…' : ''}',
      );
      await BrowserController.instance.refresh(silent: true);
    }
    return removed;
  }

  /// Free/total space on the phone.
  Future<StorageInfo?> storage() async {
    if (!_ready) return null;
    return AdbClient.instance.storageInfo();
  }

  /// Recursive size of a device folder. Slow on large trees — show progress.
  Future<int> folderSize(String path) async {
    if (!_ready) return -1;
    return AdbClient.instance.dirSizeBytes(path);
  }

  static String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i > 0 ? path.substring(0, i) : path;
  }

  void _report(bool ok, String success, String failure) {
    Services.log.connection(ok ? LogLevel.success : LogLevel.error,
        ok ? success : failure);
  }
}