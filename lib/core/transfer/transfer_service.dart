import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../state/browser_controller.dart';
import '../adb/adb_client.dart';
import '../adb/adb_models.dart';
import '../config/app_config.dart';
import '../log/log_service.dart';

/// What to do with a push whose destination on the phone is newer than the
/// local file.
enum _ConflictAction { push, skip, hold }

/// Sequential transfer queue with per-byte pull progress.
/// Single source of truth for the Transfers view and the header progress chip.
class TransferService extends ChangeNotifier {
  TransferService._();
  static final TransferService instance = TransferService._();

  final List<TransferJob> _jobs = [];
  bool _running = false;
  final Set<String> _cancelled = {};

  List<TransferJob> get jobs => List.unmodifiable(_jobs);
  List<TransferJob> get active => _jobs
      .where((j) =>
          j.status == TransferStatus.queued ||
          j.status == TransferStatus.running ||
          j.status == TransferStatus.paused)
      .toList();

  /// Anything that failed and can be retried.
  List<TransferJob> get retryable =>
      _jobs.where((j) => j.status == TransferStatus.failed).toList();

  bool get hasPaused => _jobs.any((j) => j.status == TransferStatus.paused);

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

  /// Pauses a queued job, or the whole queue via [all]. A running job is left
  /// alone: interrupting a half-written file mid-transfer is worse than
  /// finishing it, so pause only takes effect at the next item boundary.
  void pause(String jobId) {
    final job = _jobs.firstWhere((j) => j.id == jobId, orElse: () => _dummy);
    if (identical(job, _dummy)) return;
    if (job.status != TransferStatus.queued) return;
    job.status = TransferStatus.paused;
    notifyListeners();
    LogService.instance.transfer(LogLevel.info, 'Paused: ${job.label}');
  }

  void pauseAll() {
    var n = 0;
    for (final job in _jobs) {
      if (job.status == TransferStatus.queued) {
        job.status = TransferStatus.paused;
        n++;
      }
    }
    if (n == 0) return;
    notifyListeners();
    LogService.instance.transfer(LogLevel.info, 'Paused $n queued job(s)');
  }

  /// Resumes one job, or everything paused via [all].
  void resume(String jobId) {
    final job = _jobs.firstWhere((j) => j.id == jobId, orElse: () => _dummy);
    if (identical(job, _dummy)) return;
    if (job.status != TransferStatus.paused) return;
    job.status = TransferStatus.queued;
    job.error = null;
    notifyListeners();
    _pump();
  }

  void resumeAll() {
    var n = 0;
    for (final job in _jobs) {
      if (job.status == TransferStatus.paused) {
        job.status = TransferStatus.queued;
        job.error = null;
        n++;
      }
    }
    if (n == 0) return;
    notifyListeners();
    LogService.instance.transfer(LogLevel.info, 'Resumed $n job(s)');
    _pump();
  }

  /// Re-queues only the items of a failed job that did not transfer.
  ///
  /// The successful items stay counted as done, so a retry of a 50-file job
  /// that failed on file 49 re-sends one file rather than all fifty.
  void retryFailed(String jobId) {
    final index = _jobs.indexWhere((j) => j.id == jobId);
    if (index < 0) return;
    final job = _jobs[index];
    if (job.status != TransferStatus.failed && job.status != TransferStatus.cancelled) {
      return;
    }
    final failedItems = job.items.where((i) => i.sentBytes <= 0).toList();
    if (failedItems.isEmpty) {
      LogService.instance.transfer(
          LogLevel.info, 'Nothing to retry in ${job.label}');
      return;
    }
    // totalBytes and sentBytes are derived from [items], so clearing and
    // re-seeding the item list is what resets the byte totals — there is no
    // separate counter to zero.
    for (final item in failedItems) {
      item.sentBytes = 0;
    }
    job.items
      ..clear()
      ..addAll(failedItems);
    job.doneItems = 0;
    job.startedAt = DateTime.now();
    job.finishedAt = null;
    job.error = null;
    job.status = TransferStatus.queued;
    notifyListeners();
    LogService.instance.transfer(LogLevel.info,
        'Retrying ${failedItems.length} item(s) in ${job.label}');
    _pump();
  }

  void retryAllFailed() {
    final ids = _jobs
        .where((j) => j.status == TransferStatus.failed)
        .map((j) => j.id)
        .toList(growable: false);
    for (final id in ids) {
      retryFailed(id);
    }
  }

  /// Moves a queued or paused job within the queue.
  ///
  /// Newest-first display means "up" is later in [_jobs]. Jobs that already
  /// started are pinned: reordering a running job would silently change what
  /// the user queued behind it.
  bool move(String jobId, int delta) {
    final index = _jobs.indexWhere((j) => j.id == jobId);
    if (index < 0) return false;
    final job = _jobs[index];
    if (job.status != TransferStatus.queued && job.status != TransferStatus.paused) {
      return false;
    }
    final target = index + delta;
    if (target < 0 || target >= _jobs.length) return false;
    if (_jobs[target].status != TransferStatus.queued &&
        _jobs[target].status != TransferStatus.paused) {
      return false;
    }
    _jobs.removeAt(index);
    _jobs.insert(target, job);
    notifyListeners();
    return true;
  }

  void clearFinished() {
    // Paused is still pending work, not finished work — clearing it here would
    // silently throw away a queue the user deliberately parked.
    _jobs.removeWhere((j) =>
        j.status != TransferStatus.queued &&
        j.status != TransferStatus.running &&
        j.status != TransferStatus.paused);
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

  /// Decides what to do about a push whose destination already exists.
  /// Returns [_ConflictAction.push] unless the phone's copy is strictly newer
  /// *and* a non-overwrite policy is configured. A destination that does not
  /// exist, or a local file that is newer or the same age, always pushes —
  /// only the "you are about to lose newer data" case is interesting.
  Future<_ConflictAction> _resolveConflict(TransferItem item) async {
    if (AppConfig.instance.conflictPolicy == ConflictPolicy.overwrite) {
      return _ConflictAction.push;
    }
    // Reads the local mtime; a stat failure means we cannot prove a conflict.
    final localFile = File(item.source);
    final localMtime = await localFile.lastModified().then(
          (d) => d.millisecondsSinceEpoch ~/ 1000,
          onError: (_) => -1,
        );
    if (localMtime < 0) return _ConflictAction.push;

    final remote = await AdbClient.instance.statOne(item.target);
    if (remote == null || remote.modified <= localMtime) {
      return _ConflictAction.push;
    }

    final policy = AppConfig.instance.conflictPolicy;
    final note = 'phone copy is newer '
        '(${DateTime.fromMillisecondsSinceEpoch(remote.modified * 1000)})';
    if (policy == ConflictPolicy.keepNewer) {
      item.conflicted = false;
      item.conflictNote = 'skipped — $note';
      LogService.instance.transfer(LogLevel.warning,
          'Skipped ${item.target.split('/').last} — $note');
      return _ConflictAction.skip;
    }
    // ask
    item.conflicted = true;
    item.conflictNote = note;
    LogService.instance.transfer(LogLevel.warning,
        'Conflict: ${item.target.split('/').last} — $note. Held for review.');
    return _ConflictAction.hold;
  }

  /// Resolves a held conflict in the user's favour: overwrite the phone.
  void overwriteConflicts(String jobId) {
    for (final job in _jobs) {
      if (job.id != jobId) continue;
      for (final item in job.items) {
        if (!item.conflicted) continue;
        item.conflicted = false;
        item.conflictNote = null;
        item.sentBytes = 0;
      }
      job.doneItems = 0;
      job.status = TransferStatus.queued;
      job.error = null;
      job.finishedAt = null;
      job.startedAt = DateTime.now();
      notifyListeners();
      _pump();
      return;
    }
  }

  /// Resolves a held conflict the other way: keep what is on the phone.
  void keepRemoteConflicts(String jobId) {
    for (final job in _jobs) {
      if (job.id != jobId) continue;
      job.items.removeWhere((i) => i.conflicted);
      job.error = null;
      job.finishedAt = DateTime.now();
      job.status = job.items.isEmpty
          ? TransferStatus.done
          : TransferStatus.cancelled;
      notifyListeners();
      LogService.instance.transfer(LogLevel.info,
          'Kept phone copies for ${job.label}');
      return;
    }
  }

  /// Every item across all jobs currently held for conflict review.
  List<(TransferJob, TransferItem)> get conflicts => [
        for (final job in _jobs)
          for (final item in job.items)
            if (item.conflicted) (job, item),
      ];

  Future<void> _runJob(TransferJob job) async {
    job.status = TransferStatus.running;
    notifyListeners();
    final log = LogService.instance;
    var ok = 0;
    var failed = 0;
    var skipped = 0;

    for (final item in job.items) {
      if (_cancelled.remove(job.id)) {
        job.status = TransferStatus.cancelled;
        job.finishedAt = DateTime.now();
        log.transfer(LogLevel.warning, 'Cancelled: ${job.label}');
        notifyListeners();
        return;
      }
      // Already-held conflicts are a user decision, not a retry: skip them so
      // the rest of the job can finish instead of failing on them again.
      if (item.conflicted) {
        failed++;
        continue;
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
          // Conflict check before anything is written: if the phone already
          // has a *newer* file at this exact destination, pushing silently
          // destroys the user's newer work.
          final decision = await _resolveConflict(item);
          if (decision == _ConflictAction.hold) {
            failed++;
            continue;
          }
          if (decision == _ConflictAction.skip) {
            skipped++;
            continue;
          }
          final okPush = await AdbClient.instance.push(item.source, _dirOf(item.target));
          if (!okPush) throw StateError('adb push failed');
          final f = File(item.source);
          item.sentBytes = item.totalBytes = await f.length();
          item.conflicted = false;
          item.conflictNote = null;
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
      job.error = skipped > 0 ? 'all $skipped item(s) skipped (newer on phone)' : 'all $failed items failed';
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
