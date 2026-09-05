import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../state/browser_controller.dart';
import '../adb/adb_client.dart';
import '../adb/adb_models.dart';
import '../config/app_config.dart';
import '../log/log_service.dart';

/// Sequential transfer queue with per-byte pull progress.
/// Single source of truth for the Transfers view and the header progress chip.
class TransferService extends ChangeNotifier {
  TransferService._();
  static final TransferService instance = TransferService._();

  final List<TransferJob> _jobs = [];
  bool _running = false;
  final Set<String> _cancelled = {};

  List<TransferJob> get jobs => List.unmodifiable(_jobs);
  List<TransferJob> get active =>
      _jobs.where((j) => j.status == TransferStatus.queued || j.status == TransferStatus.running).toList();
  bool get isBusy => _running || active.isNotEmpty;

  String enqueuePull(List<PhoneFile> files, String destDir) {
    final items = files
        .map((f) => TransferItem(
              source: f.path,
              target: uniqueLocalPath(destDir, f.name),
              totalBytes: f.size > 0 ? f.size : -1,
            ))
        .toList();
    final job = TransferJob(
      id: 'pull-${DateTime.now().microsecondsSinceEpoch}',
      kind: TransferKind.pull,
      label: 'Pull ${files.length} file${files.length == 1 ? '' : 's'} → $destDir',
      items: items,
    );
    _jobs.insert(0, job);
    _trim();
    notifyListeners();
    _pump();
    return job.id;
  }

  String enqueuePush(List<String> localPaths, String deviceDir) {
    final items = localPaths
        .map((p) => TransferItem(
              source: p,
              target: '${deviceDir.endsWith('/') ? deviceDir : '$deviceDir/'}'
                  '${p.split(Platform.pathSeparator).last}',
            ))
        .toList();
    final job = TransferJob(
      id: 'push-${DateTime.now().microsecondsSinceEpoch}',
      kind: TransferKind.push,
      label: 'Push ${localPaths.length} item${localPaths.length == 1 ? '' : 's'} → $deviceDir',
      items: items,
    );
    _jobs.insert(0, job);
    _trim();
    notifyListeners();
    _pump();
    return job.id;
  }

  void cancel(String jobId) {
    _cancelled.add(jobId);
    final job = _jobs.firstWhere((j) => j.id == jobId, orElse: () => _dummy);
    if (identical(job, _dummy)) return;
    if (job.status == TransferStatus.queued) {
      job.status = TransferStatus.cancelled;
      job.finishedAt = DateTime.now();
      notifyListeners();
    }
  }

  void clearFinished() {
    _jobs.removeWhere(
        (j) => j.status != TransferStatus.queued && j.status != TransferStatus.running);
    notifyListeners();
  }

  static final TransferJob _dummy = TransferJob(id: '', kind: TransferKind.pull, label: '', items: []);

  void _trim() {
    if (_jobs.length <= 60) return;
    _jobs.removeRange(60, _jobs.length);
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = _jobs.lastWhere(
          (j) => j.status == TransferStatus.queued,
          orElse: () => _dummy,
        );
        if (identical(next, _dummy)) break;
        if (_cancelled.remove(next.id)) {
          next.status = TransferStatus.cancelled;
          next.finishedAt = DateTime.now();
          continue;
        }
        await _runJob(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runJob(TransferJob job) async {
    job.status = TransferStatus.running;
    notifyListeners();
    final log = LogService.instance;
    var ok = 0;
    var failed = 0;

    for (final item in job.items) {
      if (_cancelled.remove(job.id)) {
        job.status = TransferStatus.cancelled;
        job.finishedAt = DateTime.now();
        log.transfer(LogLevel.warning, 'Cancelled: ${job.label}');
        notifyListeners();
        return;
      }
      try {
        if (job.kind == TransferKind.pull) {
          final dest = File(item.target);
          await dest.parent.create(recursive: true);
          await AdbClient.instance.catToFile(item.source, dest, onChunk: (chunk) {
            item.sentBytes += chunk;
            notifyListeners();
          });
          item.sentBytes = item.totalBytes > 0 ? item.totalBytes : item.sentBytes;
        } else {
          final okPush = await AdbClient.instance.push(item.source, _dirOf(item.target));
          if (!okPush) throw StateError('adb push failed');
          final f = File(item.source);
          item.sentBytes = item.totalBytes = await f.length();
          // The phone's contents changed — cached listings for that folder
          // must not be served again.
          BrowserController.instance.invalidatePath(_dirOf(item.target));
        }
        ok++;
      } catch (e) {
        failed++;
        log.transfer(LogLevel.error, 'Failed ${job.kind.name} ${item.source} — $e');
      } finally {
        job.doneItems++;
        notifyListeners();
      }
    }

    job.finishedAt = DateTime.now();
    if (failed == 0) {
      job.status = TransferStatus.done;
      log.transfer(LogLevel.success,
          '${job.kind == TransferKind.pull ? 'Pulled' : 'Pushed'} $ok file${ok == 1 ? '' : 's'} — ${job.label}');
    } else if (ok == 0) {
      job.status = TransferStatus.failed;
      job.error = 'all $failed items failed';
      log.transfer(LogLevel.error, '${job.label} — all items failed');
    } else {
      job.status = TransferStatus.failed;
      job.error = '$failed of ${job.items.length} failed';
      log.transfer(LogLevel.warning, '${job.label} — $ok ok, $failed failed');
    }
    notifyListeners();
  }

  static String _dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i > 0 ? path.substring(0, i) : path;
  }

  /// Colliding names get "name (1).ext" suffixes, matching browser behavior.
  static String uniqueLocalPath(String dir, String name) {
    var candidate = '$dir${Platform.pathSeparator}$name';
    if (!File(candidate).existsSync()) return candidate;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      candidate = '$dir${Platform.pathSeparator}$stem ($i)$ext';
      if (!File(candidate).existsSync()) return candidate;
    }
    return '$dir${Platform.pathSeparator}$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  static String get defaultSaveDir => AppConfig.instance.saveDir;
}
