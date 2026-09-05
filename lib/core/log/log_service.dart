import 'dart:io';

import 'package:flutter/foundation.dart';

/// Categories surface as filter chips in the Activity view.
enum LogCategory { connection, transfer, browse, app }

enum LogLevel { info, success, warning, error }

class LogEvent {
  final DateTime ts;
  final LogCategory category;
  final LogLevel level;
  final String message;
  LogEvent(this.category, this.level, this.message)
      : ts = DateTime.now();
}

/// In-memory ring buffer of everything the app does, with live per-category
/// counts — the SSOT behind the Activity Log view.
class LogService extends ChangeNotifier {
  LogService._();
  static final LogService instance = LogService._();

  static const int maxEvents = 2000;

  final List<LogEvent> _events = [];
  final Map<LogCategory, int> _counts = {
    for (final c in LogCategory.values) c: 0,
  };

  List<LogEvent> get events => List.unmodifiable(_events);
  Map<LogCategory, int> get counts => Map.unmodifiable(_counts);
  int get total => _events.length;

  void log(LogCategory category, LogLevel level, String message) {
    _events.add(LogEvent(category, level, message));
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }
    _counts.update(category, (v) => v + 1);
    notifyListeners();
  }

  void connection(LogLevel l, String m) => log(LogCategory.connection, l, m);
  void transfer(LogLevel l, String m) => log(LogCategory.transfer, l, m);
  void browse(LogLevel l, String m) => log(LogCategory.browse, l, m);
  void app(LogLevel l, String m) => log(LogCategory.app, l, m);

  void clear() {
    _events.clear();
    for (final c in LogCategory.values) {
      _counts[c] = 0;
    }
    notifyListeners();
  }

  String exportText({LogCategory? category}) {
    final buf = StringBuffer();
    for (final e in _events) {
      if (category != null && e.category != category) continue;
      buf.writeln(
          '[${e.ts.toIso8601String()}] [${e.category.name.toUpperCase()}] [${e.level.name.toUpperCase()}] ${e.message}');
    }
    return buf.toString();
  }

  Future<File?> exportToFile(String directory, {LogCategory? category}) async {
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final f = File('${dir.path}${Platform.pathSeparator}phonesync-log-$stamp.txt');
      await f.writeAsString(exportText(category: category));
      return f;
    } catch (_) {
      return null;
    }
  }
}
