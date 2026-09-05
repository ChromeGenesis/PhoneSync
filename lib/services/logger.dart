/// Minimal console logger used by the theme service and widgets.
/// The user-facing activity log lives in `core/log/log_service.dart`.
class Logger {
  static void info(String message) => _log('INFO', message);
  static void warn(String message) => _log('WARN', message);
  static void error(String message) => _log('ERROR', message);
  static void debug(String message) => _log('DEBUG', message);

  static void _log(String level, String message) {
    // ignore: avoid_print
    print('[$level] $message');
  }
}
