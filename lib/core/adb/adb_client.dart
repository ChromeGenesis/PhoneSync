import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'adb_models.dart';

class AdbResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const AdbResult(this.exitCode, this.stdout, this.stderr);
  bool get ok => exitCode == 0;
}

/// Single source of truth for every adb process this app spawns.
///
/// All phone I/O funnels through here so connection state, timeouts, and
/// quoting behave identically everywhere.
class AdbClient {
  AdbClient._();
  static final AdbClient instance = AdbClient._();

  /// Resolved lazily so a missing adb only fails the call that needs it.
  String adbExecutable = 'adb';

  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Process? proc;
    try {
      // Process.start (not Process.run) so a timeout can KILL the adb.exe —
      // an unkillable timed-out process stays alive and keeps holding a slot
      // on the device transport, which wedges every later command.
      proc = await Process.start(adbExecutable, args);
      final out = StringBuffer();
      final err = StringBuffer();
      final outSub = proc.stdout.transform(utf8.decoder).listen(out.write);
      final errSub = proc.stderr.transform(utf8.decoder).listen(err.write);
      final killer = Timer(timeout, proc.kill);
      final code = await proc.exitCode;
      killer.cancel();
      await outSub.cancel();
      await errSub.cancel();
      return AdbResult(code, out.toString(), err.toString());
    } on ProcessException catch (e) {
      return AdbResult(-1, '', e.message);
    } finally {
      // Belt-and-braces: never leave a stray process behind.
      proc?.kill();
    }
  }

  /// `adb shell <command>` with a pre-quoted command string.
  Future<AdbResult> shell(String command, {Duration timeout = const Duration(seconds: 15)}) =>
      run(['shell', command], timeout: timeout);

  /// Starts a long-lived process and exposes raw stdout (binary-safe for
  /// `exec-out`). Caller owns the process handle.
  Future<Process?> start(List<String> args) async {
    try {
      return await Process.start(adbExecutable, args);
    } on ProcessException {
      return null;
    }
  }

  /// Files per batched `stat` round trip. Large enough that a 500-file
  /// folder needs ~13 round trips instead of ~25, small enough that one
  /// command line stays well under device arg limits.
  static const _statBatchSize = 48;

  // ---------------------------------------------------------------- quoting

  /// Quote a single path for use inside an adb shell command.
  static String q(String path) {
    final escaped = path.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$');
    return '"$escaped"';
  }

  // ---------------------------------------------------------------- devices

  /// Parses `adb devices -l`; returns entries in the `device` state only.
  Future<List<AdbDevice>> listDevices() async {
    final res = await run(['devices', '-l']);
    if (!res.ok) return const [];
    final devices = <AdbDevice>[];
    for (final line in res.stdout.split('\n').skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2 || parts[1] != 'device') continue;
      final id = parts[0];
      var model = '';
      for (final p in parts.skip(2)) {
        if (p.startsWith('model:')) model = p.substring(6);
      }
      devices.add(AdbDevice(id: id, model: model, isWireless: id.contains(':')));
    }
    return devices;
  }

  Future<String?> deviceModel(String id) async {
    final res = await run(['-s', id, 'shell', 'getprop ro.product.model'],
        timeout: const Duration(seconds: 8));
    final model = res.stdout.trim();
    return model.isEmpty ? null : model;
  }

  Future<bool> connect(String hostPort) async {
    final res = await run(['connect', hostPort], timeout: const Duration(seconds: 8));
    // adb prints "connected to ..." or "already connected to ..." on success.
    return res.ok && !res.stdout.contains('failed') && !res.stdout.contains('cannot');
  }

  Future<void> disconnect(String hostPort) async {
    await run(['disconnect', hostPort]);
  }

  // ---------------------------------------------------------------- listing

  /// Streams file names of [dir], newest first (matches old app's `ls -1t`).
  Future<List<String>> listNames(String dir) async {
    final res = await shell('ls -1t ${q(dir)}', timeout: const Duration(seconds: 12));
    if (!res.ok) return const [];
    return res.stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l != 'opendir failed' && !l.startsWith('ls:'))
        .toList(growable: false);
  }

  /// Stat a batch of full device paths in ONE adb round trip.
  ///
  /// toybox `stat` exits non-zero if any path is missing but still prints
  /// rows for the ones it found, so stdout is parsed even on failure.
  Future<List<PhoneFile>> statPaths(List<String> paths) async {
    if (paths.isEmpty) return const [];
    final quoted = paths.map(q).toList();
    // ':' separators, never '|' — a dropped quote through any shell layer
    // would turn '|' into a device-side pipe. ':' is safe everywhere.
    final res = await shell("stat -c '%Y:%s:%F:%n' ${quoted.join(' ')} 2>/dev/null",
        timeout: const Duration(seconds: 12));
    final files = <PhoneFile>[];
    final seen = <String>{};
    for (final line in res.stdout.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final first = l.indexOf(':');
      final second = l.indexOf(':', first + 1);
      final third = l.indexOf(':', second + 1);
      if (first < 0 || second < 0 || third < 0) continue;
      final mtime = int.tryParse(l.substring(0, first)) ?? 0;
      final size = int.tryParse(l.substring(first + 1, second)) ?? -1;
      final kind = l.substring(second + 1, third);
      final fullPath = l.substring(third + 1).replaceAll('//', '/');
      final name = fullPath.split('/').where((s) => s.isNotEmpty).lastOrNull ?? fullPath;
      seen.add(fullPath);
      files.add(PhoneFile(
        name: name,
        path: fullPath,
        size: size,
        modified: mtime,
        isDir: kind == 'directory',
      ));
    }
    // Paths stat couldn't resolve still show up (name only), so the listing
    // never silently loses entries.
    for (final p in paths) {
      if (!seen.contains(p)) {
        files.add(PhoneFile(name: p.split('/').last, path: p));
      }
    }
    return files;
  }

  /// Stat a batch of names under one parent directory.
  Future<List<PhoneFile>> statBatch(String parentDir, List<String> names) =>
      statPaths([for (final n in names) joinPath(parentDir, n)]);

  /// Full directory listing: one `ls -1t` + batched `stat` round trips.
  Future<List<PhoneFile>> listDir(String dir) async {
    final names = await listNames(dir);
    final out = <PhoneFile>[];
    for (var i = 0; i < names.length; i += _statBatchSize) {
      final end = (i + _statBatchSize > names.length) ? names.length : i + _statBatchSize;
      out.addAll(await statBatch(dir, names.sublist(i, end)));
    }
    return out;
  }

  /// Recent file paths only (no stat round trips) — cheap enough for the
  /// live poll to run every few seconds and catch deletions fast.
  Future<List<String>> listRecentPaths({int limit = 200}) async {
    try {
      // `head` runs ON the device: without it, content query enumerates the
      // entire media table (tens of thousands of rows) before we can cut it.
      final res = await shell(
        'content query --uri content://media/external/file '
        "--projection _data --sort 'date_modified DESC' | head -n $limit",
        timeout: const Duration(seconds: 20),
      );
      if (!res.stdout.contains('_data=')) return const [];
      final paths = <String>[];
      for (final line in res.stdout.split('\n')) {
        final i = line.indexOf('_data=');
        if (i < 0) continue;
        var path = line.substring(i + 6).trim();
        if (path.isEmpty) continue;
        path = path.replaceFirst('/storage/emulated/0', '/sdcard');
        paths.add(path);
        if (paths.length >= limit) break;
      }
      return paths;
    } catch (_) {
      return const [];
    }
  }

  /// Global media index, newest first (old app's RECENTS view).
  ///
  /// Only `_data` projection is portable across OEM content implementations,
  /// so size/mtime are filled in afterwards with batched `stat` calls.
  /// Never throws — a failed media query yields an empty listing.
  Future<List<PhoneFile>> listRecents({int limit = 200}) async {
    try {
      final paths = await listRecentPaths(limit: limit);
      final out = <PhoneFile>[];
      for (var i = 0; i < paths.length; i += _statBatchSize) {
        final end = (i + _statBatchSize > paths.length) ? paths.length : i + _statBatchSize;
        out.addAll(await statPaths(paths.sublist(i, end)));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Top-level folders under /sdcard (old app's auto-discovered folder chips).
  Future<List<String>> sdcardFolders() async {
    final res = await shell(r'ls -d /sdcard/*/ 2>/dev/null',
        timeout: const Duration(seconds: 10));
    if (!res.ok) return const [];
    return res.stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('/sdcard/') && l.endsWith('/'))
        .map((l) => l.substring(0, l.length - 1))
        .where((p) {
          final n = p.split('/').last;
          return !n.startsWith('.');
        })
        .toList(growable: false);
  }

  // ------------------------------------------------------------------- I/O

  /// Streams a device file's bytes over `exec-out` (binary safe).
  /// Reports progress via [onChunk]. Returns total bytes read.
  Future<int> catToFile(String devicePath, File dest, {void Function(int)? onChunk}) async {
    final proc = await start(['exec-out', 'cat', devicePath]);
    if (proc == null) throw StateError('failed to start adb exec-out');
    var total = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in proc.stdout) {
        total += chunk.length;
        sink.add(chunk);
        onChunk?.call(chunk.length);
      }
      await sink.flush();
      await sink.close();
      final code = await proc.exitCode;
      if (code != 0) throw StateError('exec-out cat exited $code');
    } catch (_) {
      await sink.close();
      rethrow;
    }
    return total;
  }

  Future<Uint8List> catBytes(String devicePath, {int maxBytes = 32 * 1024 * 1024}) async {
    final proc = await start(['exec-out', 'cat', devicePath]);
    if (proc == null) throw StateError('failed to start adb exec-out');
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in proc.stdout) {
      total += chunk.length;
      if (total > maxBytes) {
        proc.kill();
        throw StateError('file exceeds preview limit');
      }
      builder.add(chunk);
    }
    await proc.exitCode;
    return builder.takeBytes();
  }

  Future<bool> push(String localPath, String deviceDir) async {
    final res = await run(['push', localPath, deviceDir], timeout: const Duration(minutes: 30));
    return res.ok;
  }

  // ---------------------------------------------------------------- intents

  Future<bool> openUrl(String url) async {
    final res = await shell(
        'am start -a android.intent.action.VIEW -d ${q(url)}');
    return res.ok;
  }

  Future<bool> sendText(String text) async {
    final res = await shell(
        'am start -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT ${q(text)}');
    return res.ok;
  }
}

/// POSIX-style join that keeps `/sdcard` roots intact.
String joinPath(String dir, String name) {
  if (dir.endsWith('/')) return '$dir$name';
  return '$dir/$name';
}
