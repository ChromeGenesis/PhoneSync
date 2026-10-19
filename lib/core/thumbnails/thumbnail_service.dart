import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../adb/adb_client.dart';
import '../adb/adb_models.dart';
import '../config/app_dirs.dart';

/// Two-tier thumbnail cache (memory LRU + disk) for device image files.
///
/// Bytes stream over `adb exec-out cat`, then are downscaled to 128px and
/// cached on disk keyed by path + mtime + size, so a file is pulled at most
/// once until it changes.
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  static const _memLimit = 120;
  final Map<String, ImageProvider> _memory = {};
  final Map<String, Future<ImageProvider?>> _inFlight = {};
  Directory? _diskDir;

  Directory get _cacheDir {
    return _diskDir ??= Directory(AppDirs.cacheDir)..createSync(recursive: true);
  }

  ImageProvider? peek(PhoneFile f) => _memory[_key(f)];

  /// Cached provider if available, else starts the async fetch.
  ImageProvider? get(PhoneFile f) {
    if (!f.isImage) return null;
    final key = _key(f);
    final cached = _memory[key];
    if (cached != null) return cached;
    _inFlight.putIfAbsent(key, () => _fetch(f, key)).whenComplete(() {
      _inFlight.remove(key);
    });
    return _memory[key];
  }

  Future<ImageProvider> load(PhoneFile f) async {
    final p = get(f);
    if (p != null) return p;
    return await _inFlight[_key(f)] ?? _fetch(f, _key(f)).then((v) => v ?? _blank);
  }

  static final ImageProvider _blank = MemoryImage(Uint8List(0));

  String _key(PhoneFile f) =>
      '${f.path.hashCode.toRadixString(36)}-${f.modified}-${f.size}';

  Future<ImageProvider?> _fetch(PhoneFile f, String key) async {
    final diskFile = File('${_cacheDir.path}${Platform.pathSeparator}$key.png');
    try {
      if (await diskFile.exists()) {
        final provider = FileImage(diskFile);
        _remember(key, provider);
        return provider;
      }
      final bytes = await AdbClient.instance.catBytes(f.path, maxBytes: 48 * 1024 * 1024);
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 128,
        targetHeight: 128,
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (png == null) return null;
      await diskFile.writeAsBytes(png.buffer.asUint8List(), flush: true);
      final provider = FileImage(diskFile);
      _remember(key, provider);
      return provider;
    } catch (_) {
      return null;
    }
  }

  void _remember(String key, ImageProvider provider) {
    if (_memory.length >= _memLimit) {
      _memory.remove(_memory.keys.first);
    }
    _memory[key] = provider;
  }

  /// Called on disconnect so stale thumbnails for the previous device's paths
  /// don't get confused with the next device's.
  void clearInFlight() => _inFlight.clear();
}
