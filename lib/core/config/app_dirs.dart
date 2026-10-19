import 'dart:io';

/// Platform-correct locations for PhoneSync's own files.
///
/// These follow each platform's convention rather than assuming POSIX: macOS
/// uses `~/Library/...`, Windows uses `%APPDATA%`/`%LOCALAPPDATA%`, Linux follows
/// XDG. Getting this wrong is not fatal but it is wrong — most visibly, macOS
/// periodically purges `/var/folders`, so a cache parked in the system temp dir
/// evaporates for no reason.
class AppDirs {
  AppDirs._();

  static const _appName = 'PhoneSync';

  static final String _home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  /// Durable settings — survives reboots, user-visible, not auto-purged.
  ///
  /// - macOS:   ~/Library/Application Support/PhoneSync
  /// - Windows: %APPDATA%\PhoneSync
  /// - Linux:   $XDG_CONFIG_HOME (or ~/.config)/PhoneSync
  static String get configDir {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return _join(appData, _appName);
      }
    } else if (Platform.isMacOS) {
      if (_home.isNotEmpty) {
        return _join(_home, 'Library', 'Application Support', _appName);
      }
    } else {
      final xdg = env['XDG_CONFIG_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        return _join(xdg, _appName);
      }
      if (_home.isNotEmpty) return _join(_home, '.config', _appName);
    }
    // Last resort: alongside the temp dir rather than at the filesystem root.
    return _join(Directory.systemTemp.path, _appName);
  }

  /// Rebuildable cache — safe to delete, may be purged by the OS.
  ///
  /// - macOS:   ~/Library/Caches/PhoneSync
  /// - Windows: %LOCALAPPDATA%\PhoneSync\Cache
  /// - Linux:   $XDG_CACHE_HOME (or ~/.cache)/PhoneSync
  static String get cacheDir {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final local = env['LOCALAPPDATA'];
      if (local != null && local.isNotEmpty) {
        return _join(local, _appName, 'Cache');
      }
    } else if (Platform.isMacOS) {
      // Deliberately NOT systemTemp: macOS purges /var/folders on a schedule,
      // which would silently throw away the thumbnail cache every few days.
      if (_home.isNotEmpty) {
        return _join(_home, 'Library', 'Caches', _appName);
      }
    } else {
      final xdg = env['XDG_CACHE_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        return _join(xdg, _appName);
      }
      if (_home.isNotEmpty) return _join(_home, '.cache', _appName);
    }
    return _join(Directory.systemTemp.path, _appName, 'Cache');
  }

  /// Default download destination — `~/Downloads` on every desktop platform.
  static String get defaultSaveDir {
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        return _join(profile, 'Downloads');
      }
    } else if (_home.isNotEmpty) {
      return _join(_home, 'Downloads');
    }
    return Directory.systemTemp.path;
  }

  static String _join(String a, [String? b, String? c, String? d]) {
    final parts = [a, b, c, d].where((p) => p != null && p.isNotEmpty).toList();
    return parts.join(Platform.pathSeparator);
  }
}