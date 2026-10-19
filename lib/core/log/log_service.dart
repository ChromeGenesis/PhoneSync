import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_dirs.dart';

/// Categories surface as filter chips in the Activity view.
enum LogCategory { connection, transfer, browse, app }

enum LogLevel { info, success, warning, error }

class LogEvent {
  final DateTime ts;
  final LogCategory category;
  final LogLevel level;
  final String message;
  LogEvent(this.category, this.level, this.message, {DateTime? ts})
      : ts = ts ?? DateTime.now();

  Map<String, Object?> toJson() => {
        't': ts.toIso8601String(),
        'c': category.name,
        'l': level.name,
        'm': message,
      };

  static LogEvent? fromJson(Map<String, Object?> j) {
    final ts = DateTime.tryParse(j['t'] as String? ?? '');
    final msg = j['m'];
    if (ts == null || msg is! String) return null;
    final category = _byName(LogCategory.values, j['c']);
    final level = _byName(LogLevel.values, j['l']);
    if (category == null || level == null) return null;
    return LogEvent(category, level, msg, ts: ts);
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// In-memory ring buffer of everything the app does, with live per-category
/// counts — the SSOT behind the Activity Log view.
///
/// Also persisted to disk as JSON Lines so the log survives a restart. Without
/// it the view starts empty on every launch, and the record of whatever went
/// wrong is gone exactly when you want to read it.
class LogService extends ChangeNotifier {
  LogService._();
  static final LogService instance = LogService._();

  static const int maxEvents = 2000;

  /// How many events the on-disk log keeps before the oldest are trimmed.
  static const int maxPersisted = 5000;

  final List<LogEvent> _events = [];
  final Map<LogCategory, int> _counts = {
    for (final c in LogCategory.values) c: 0,
  };

  /// Recorded but not yet written to disk.
  final List<LogEvent> _unflushed = [];

  Timer? _flushTimer;
  bool _persist = true;
  bool _loaded = false;

  bool get persistenceEnabled => _persist;

  List<LogEvent> get events => List.unmodifiable(_events);
  Map<LogCategory, int> get counts => Map.unmodifiable(_counts);
  int get total => _events.length;

  /// Restores the previous run's log. Call once during startup, before the
  /// first event is recorded.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(_logFilePath);
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      final restored = <LogEvent>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = json.decode(line);
          if (decoded is Map<String, Object?>) {
            final e = LogEvent.fromJson(decoded);
            if (e != null) restored.add(e);
          }
        } catch (_) {
          // A torn final line (killed mid-write) must not poison the rest.
        }
      }
      if (restored.isEmpty) return;
      // Keep only the tail that still fits the ring buffer, then recount so the
      // category chips agree with what is actually on screen.
      final start =
          restored.length > maxEvents ? restored.length - maxEvents : 0;
      _events.addAll(restored.sublist(start));
      if (_events.length > maxEvents) {
        _events.removeRange(0, _events.length - maxEvents);
      }
      for (final e in _events) {
        _counts[e.category] = (_counts[e.category] ?? 0) + 1;
      }
      notifyListeners();
    } catch (_) {}
  }

  String get _logFilePath =>
      '${AppDirs.configDir}${Platform.pathSeparator}activity.jsonl';

  void log(LogCategory category, LogLevel level, String message) {
    final event = LogEvent(category, level, message);
    _events.add(event);
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }
    _counts.update(category, (v) => v + 1);
    if (_persist) {
      _unflushed.add(event);
      _scheduleFlush();
    }
    notifyListeners();
  }

  void connection(LogLevel l, String m) => log(LogCategory.connection, l, m);
  void transfer(LogLevel l, String m) => log(LogCategory.transfer, l, m);
  void browse(LogLevel l, String m) => log(LogCategory.browse, l, m);
  void app(LogLevel l, String m) => log(LogCategory.app, l, m);

  void setPersistence(bool enabled) {
    if (enabled == _persist) return;
    _persist = enabled;
    if (enabled) {
      // Re-seed from what is already on screen so switching it back on doesn't
      // leave a gap between the last flush and now.
      _unflushed.addAll(_events);
      _scheduleFlush();
    } else {
      _flushTimer?.cancel();
      _unflushed.clear();
    }
    notifyListeners();
  }

  void clear() {
    _events.clear();
    for (final c in LogCategory.values) {
      _counts[c] = 0;
    }
    _unflushed.clear();
    _deleteLogFile();
    notifyListeners();
  }

  // ----------------------------------------------------------- persistence

  /// Coalesce writes — a live browse poll emits several events a second and
  /// none of them need to reach the disk individually.
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), _flush);
  }

  Future<void> _flush() async {
    if (_unflushed.isEmpty) return;
    final batch = List<LogEvent>.from(_unflushed);
    _unflushed.clear();
    try {
      final file = File(_logFilePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final buffer = StringBuffer();
      for (final e in batch) {
        buffer.writeln(jsonEncode(e.toJson()));
      }
      await file.writeAsString(buffer.toString(),
          mode: FileMode.append, flush: true);
      await _trimIfNeeded(file);
    } catch (_) {
      // Persistence is a convenience; never let it break logging itself.
    }
  }

  /// Rewrite the file without its oldest lines once it outgrows the cap.
  Future<void> _trimIfNeeded(File file) async {
    try {
      // ~160 bytes a line with a generous margin; under this, skip the rewrite.
      if (await file.length() < maxPersisted * 160) return;
      final lines = await file.readAsLines();
      if (lines.length <= maxPersisted) return;
      await file.writeAsString(
        '${lines.sublist(lines.length - maxPersisted).join('\n')}\n',
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _deleteLogFile() async {
    try {
      final file = File(_logFilePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- export

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

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}