import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'adb_models.dart';

/// Why an adb invocation yielded nothing usable.
///
/// The distinction is load-bearing: "the adb binary is missing" and "no phone
/// is attached" otherwise produce byte-identical empty output, and only the
/// first one is actionable by the user.
enum AdbFailure { none, adbMissing, timedOut, spawnFailed }

class AdbResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final AdbFailure failure;
  const AdbResult(this.exitCode, this.stdout, this.stderr,
      [this.failure = AdbFailure.none]);

  bool get ok => exitCode == 0 && failure == AdbFailure.none;
  bool get adbMissing => failure == AdbFailure.adbMissing;
}

/// Single source of truth for every adb process this app spawns.
///
/// All phone I/O funnels through here so connection state, timeouts, and
/// quoting behave identically everywhere.
class AdbClient {
  AdbClient._();
  static final AdbClient instance = AdbClient._();

  static const _defaultExecutable = 'adb';

  String _configured = _defaultExecutable;
  String? _resolved;
  String? _resolveFailure;

  /// What the user configured — a bare name or an absolute path.
  String get adbConfigured => _configured;

  set adbExecutable(String value) {
    if (value == _configured) return;
    _configured = value;
    _resolved = null;
    _resolveFailure = null;
  }

  /// Absolute path actually spawned, or null while adb is unlocated.
  ///
  /// Both lookups force resolution first — the failure field is only
  /// meaningful once [_resolve] has actually run.
  String? get adbResolved {
    _resolve();
    return _resolveFailure == null ? _resolved : null;
  }

  /// Why adb could not be located; null when it was located fine.
  String? get adbResolveFailure {
    _resolve();
    return _resolveFailure;
  }

  /// False when adb cannot be spawned at all — every command will fail.
  bool get adbAvailable => _resolve().isNotEmpty;

  /// Resolves the configured executable to something spawnable.
  ///
  /// A GUI app launched from Finder/Dock inherits launchd's environment, where
  /// PATH is typically unset entirely — so a bare `adb` resolves against
  /// /usr/bin:/bin:/usr/sbin:/sbin only and fails, even though `adb` works
  /// perfectly in the user's own shell. Probing known install locations makes
  /// the default configuration work with no setup at all.
  String _resolve() {
    final cached = _resolved;
    if (cached != null) return cached;

    final configured = _configured.trim();
    if (configured.isEmpty) {
      _resolveFailure = 'ADB executable is not set';
      return '';
    }

    // An explicit path is trusted verbatim — the user pointed at a file.
    if (configured.contains('/') || configured.contains('\\')) {
      if (File(configured).existsSync()) {
        _resolved = configured;
      } else {
        _resolveFailure = 'No adb executable at ${File(configured).path}';
      }
      return _resolved ?? '';
    }

    for (final candidate in _candidatePaths(configured)) {
      if (File(candidate).existsSync()) {
        _resolved = candidate;
        return candidate;
      }
    }
    _resolveFailure = "Could not find '$configured' on this machine";
    return '';
  }

  /// Directories to search for [name]: PATH first (so deliberate overrides
  /// win), then well-known platform-tools locations, then system defaults.
  Iterable<String> _candidatePaths(String name) sync* {
    final names = Platform.isWindows ? [name, '$name.exe'] : <String>[name];
    final dirs = <String>[];

    final path = Platform.environment['PATH'];
    if (path != null && path.isNotEmpty) {
      dirs.addAll(path.split(Platform.isWindows ? ';' : ':'));
    }

    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      dirs.addAll([
        '$home/.local/bin',
        '$home/bin',
        '$home/Library/Android/sdk/platform-tools',
        '$home/Android/Sdk/platform-tools',
        '$home/AppData/Local/Android/Sdk/platform-tools',
        '/Applications/Android Studio.app/Contents/sdk/platform-tools',
      ]);
    }

    final sdk = Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'];
    if (sdk != null && sdk.isNotEmpty) {
      dirs.add('$sdk${Platform.pathSeparator}platform-tools');
    }

    dirs.addAll([
      '/usr/local/bin',
      '/opt/homebrew/bin',
      '/usr/bin',
      '/opt/local/bin',
      '/snap/bin',
      '/var/lib/flatpak/exports/bin',
    ]);

    final emitted = <String>{};
    for (final dir in dirs) {
      if (dir.isEmpty) continue;
      for (final n in names) {
        final full = '$dir${Platform.pathSeparator}$n';
        if (emitted.add(full)) yield full;
      }
    }
  }

  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
    String? stdinData,
    bool targetDevice = true,
  }) async {
    final exe = _resolve();
    if (exe.isEmpty) {
      return AdbResult(-1, '', _resolveFailure ?? 'adb unavailable',
          AdbFailure.adbMissing);
    }

    // Once a device is adopted, every device-scoped command must name it.
    // A phone reachable over TCP/IP 5555 *and* over wireless debugging shows
    // up as two entries, and bare `adb shell` then fails outright with
    // "more than one device/emulator" — every listing, every transfer, gone.
    final target = targetDevice ? _targetDevice : null;
    final effective =
        target != null && _acceptsTarget(args) ? ['-s', target, ...args] : args;

    Process? proc;
    var timedOut = false;
    try {
      // Process.start (not Process.run) so a timeout can KILL the adb.exe —
      // an unkillable timed-out process stays alive and keeps holding a slot
      // on the device transport, which wedges every later command.
      proc = await Process.start(exe, effective);
      if (stdinData != null) {
        // `adb pair` blocks on an "Enter pairing code:" prompt, so the code has
        // to go in over stdin. A write can still fail with EPIPE when adb bails
        // before prompting (stale port, rejected key), which must not take the
        // call down — the exit code carries the real answer.
        try {
          proc.stdin.write(stdinData);
          await proc.stdin.flush();
          await proc.stdin.close();
        } catch (_) {}
      }
      final out = StringBuffer();
      final err = StringBuffer();
      final outSub = proc.stdout.transform(utf8.decoder).listen(out.write);
      final errSub = proc.stderr.transform(utf8.decoder).listen(err.write);
      final killer = Timer(timeout, () {
        timedOut = true;
        proc?.kill();
      });
      final code = await proc.exitCode;
      killer.cancel();
      await outSub.cancel();
      await errSub.cancel();
      return AdbResult(code, out.toString(), err.toString(),
          timedOut ? AdbFailure.timedOut : AdbFailure.none);
    } on ProcessException catch (e) {
      return AdbResult(-1, '', e.message, AdbFailure.spawnFailed);
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
    final exe = _resolve();
    if (exe.isEmpty) return null;
    final target = _targetDevice;
    final effective =
        target != null && _acceptsTarget(args) ? ['-s', target, ...args] : args;
    try {
      return await Process.start(exe, effective);
    } on ProcessException {
      return null;
    }
  }

  /// Commands that address the adb server or the network rather than a device,
  /// and so must never have `-s` injected.
  static const _serverCommands = {
    'connect',
    'disconnect',
    'devices',
    'pair',
    'mdns',
    'start-server',
    'kill-server',
    'version',
    'help',
    'reconnect',
  };

  bool _acceptsTarget(List<String> args) => commandIsDeviceScoped(args);

  /// Whether an adb invocation addresses a device (and so can take `-s`).
  /// Exposed so the behaviour can be asserted without reaching into internals.
  static bool commandIsDeviceScoped(List<String> args) =>
      args.isNotEmpty && !_serverCommands.contains(args.first);

  /// The device all device-scoped commands are pinned to.
  String? get targetDevice => _targetDevice;
  String? _targetDevice;

  /// Pin (or clear, with null) the active device. Call this whenever the
  /// connection state changes — a stale id makes every command fail.
  void setTargetDevice(String? id) {
    if (id == _targetDevice) return;
    _targetDevice = id;
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

  // ------------------------------------------------------- wireless pairing

  /// Devices currently advertising ADB over mDNS.
  ///
  /// This is the difference between "read the IP and port off the phone and
  /// type them into a terminal" and "it just found it" — the phone publishes
  /// these itself the moment Wireless debugging is enabled.
  Future<List<MdnsService>> mdnsServices() async {
    final res = await run(['mdns', 'services'], timeout: const Duration(seconds: 10));
    if (!res.ok) return const [];
    final out = <MdnsService>[];
    for (final line in res.stdout.split('\n')) {
      final svc = MdnsService.tryParse(line);
      if (svc != null) out.add(svc);
    }
    return out;
  }

  /// `adb pair host:port` — links this machine to a phone running Android 11+
  /// wireless debugging. [code] is the 6-digit code from the phone's
  /// "Pair device with pairing code" screen.
  ///
  /// The result is written to the machine's adb key file, so this only has to
  /// happen once per phone, ever.
  Future<AdbResult> pair(String hostPort, String code) => run(
        ['pair', hostPort],
        stdinData: '$code\n',
        timeout: const Duration(seconds: 20),
      );

  /// `adb tcpip <port>` — restarts adbd listening on a fixed TCP port.
  ///
  /// Useful because wireless debugging's own port rotates every time the toggle
  /// is switched. This does *not* survive a reboot: adbd reverts to USB-only,
  /// so after a restart the phone has to be paired again or USB used once.
  Future<AdbResult> enableTcpip(int port, {String? deviceId}) => run(
        [if (deviceId != null) ...['-s', deviceId], 'tcpip', '$port'],
        timeout: const Duration(seconds: 20),
      );

  // ------------------------------------------------------- device actions

  /// Total and free space on the phone's primary volume.
  ///
  /// `df -k` reports 1K blocks, which sidesteps the -b/-h flag differences
  /// between toybox versions without having to parse human-readable output.
  Future<StorageInfo?> storageInfo() async {
    final res = await shell("df -k /sdcard | tail -n 1", timeout: const Duration(seconds: 12));
    if (!res.ok) return null;
    final line = res.stdout.trim().split('\n').last;
    final cols = line.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();
    // Filesystem 1K-blocks Used Available Capacity Mounted-on
    if (cols.length < 4) return null;
    final total = int.tryParse(cols[1]);
    final used = int.tryParse(cols[2]);
    final free = int.tryParse(cols[3]);
    if (total == null || used == null || free == null) return null;
    return StorageInfo(
      totalBytes: total * 1024,
      freeBytes: free * 1024,
      usedBytes: used * 1024,
    );
  }

  /// Recursive size of a device directory, in bytes.
  ///
  /// `du -sk` walks the whole tree, so this is a slow call on a large folder —
  /// callers must show progress rather than treat it as instant.
  Future<int> dirSizeBytes(String path) async {
    final res = await shell('du -sk ${q(path)} 2>/dev/null',
        timeout: const Duration(seconds: 45));
    if (!res.ok) return -1;
    final first = res.stdout.trim().split('\n').firstOrNull;
    if (first == null) return -1;
    final kb = int.tryParse(first.split(RegExp(r'\s+')).first);
    return kb == null ? -1 : kb * 1024;
  }

  /// Deletes a file or directory tree on the device.
  Future<bool> deletePath(String path) async {
    final res = await shell('rm -rf ${q(path)}', timeout: const Duration(seconds: 20));
    return res.ok;
  }

  /// Opens a device file in whichever app claims its type.
  ///
  /// Uses a file:// URI rather than a MediaStore content:// one because the
  /// latter needs the media id, which is not available for arbitrary paths.
  /// --grant-read-uri-permission is required or the receiving app is denied
  /// read access and the intent appears to succeed but opens nothing.
  Future<bool> openFileOnDevice(String path) async {
    final res = await shell(
      'am start -a android.intent.action.VIEW --grant-read-uri-permission '
      '-t ${q(mimeFor(path))} -d ${q(_fileUri(path))}',
    );
    return res.ok;
  }

  /// Opens the system share sheet for a device file.
  Future<bool> shareFile(String path) async {
    final res = await shell(
      'am start -a android.intent.action.SEND --grant-read-uri-permission '
      '-t ${q(mimeFor(path))} --eu android.intent.extra.STREAM ${q(_fileUri(path))}',
    );
    return res.ok;
  }

  /// Sets an image as the home-screen wallpaper.
  Future<bool> setWallpaper(String path) async {
    final res = await shell(
      'am start -a android.intent.action.SET_WALLPAPER '
      '--grant-read-uri-permission -t image/* -d ${q(_fileUri(path))}',
    );
    return res.ok;
  }

  static String _fileUri(String path) =>
      path.startsWith('/') ? 'file://$path' : path;

  /// Best-effort MIME from extension. Deliberately small and static: a
  /// content-type lookup service is overkill for the handful of types that
  /// actually get shared or viewed from this app.
  static String mimeFor(String path) {
    final name = path.split('/').last.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      'bmp' => 'image/bmp',
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      '3gp' => 'video/3gpp',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      'ogg' => 'audio/ogg',
      'pdf' => 'application/pdf',
      'txt' || 'log' => 'text/plain',
      'zip' => 'application/zip',
      _ => '*/*',
    };
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
