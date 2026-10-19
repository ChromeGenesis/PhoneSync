import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../adb/adb_client.dart';
import '../adb/adb_models.dart';
import 'app_dirs.dart';

/// Single source of truth for every persisted setting.
///
/// Stored as JSON in the user's config dir; controllers mutate through the
/// typed setters which persist automatically.
class AppConfig extends ChangeNotifier {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  File? _file;

  String saveDir = '';
  String adbPath = 'adb';
  bool autoConnect = true;
  List<String> scanAddresses = const [
    '192.168.0.1:5555',
    '192.168.0.2:5555',
    '192.168.0.3:5555',
    '192.168.0.4:5555',
  ];
  String? lastDeviceAddress;
  List<String> phonePaths = const [
    '/sdcard/Download',
    '/sdcard/DCIM/Camera',
  ];
  List<String> pcFavorites = const [
    'Downloads',
    'Desktop',
    'Documents',
    'Pictures',
  ];
  int pollIntervalSeconds = 3;
  bool persistActivityLog = true;
  ConflictPolicy conflictPolicy = ConflictPolicy.keepNewer;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Config file location, per platform convention — see [AppDirs].
  static File _configFile() =>
      File('${AppDirs.configDir}${Platform.pathSeparator}config.json');

  Future<void> load() async {
    _file = _configFile();
    try {
      final raw = await _file!.readAsString();
      final map = json.decode(raw) as Map<String, dynamic>;
      saveDir = (map['saveDir'] as String?) ?? saveDir;
      adbPath = (map['adbPath'] as String?) ?? adbPath;
      autoConnect = (map['autoConnect'] as bool?) ?? autoConnect;
      lastDeviceAddress = map['lastDeviceAddress'] as String?;
      scanAddresses =
          ((map['scanAddresses'] as List?)?.cast<String>()) ?? scanAddresses;
      phonePaths = ((map['phonePaths'] as List?)?.cast<String>()) ?? phonePaths;
      pcFavorites =
          ((map['pcFavorites'] as List?)?.cast<String>()) ?? pcFavorites;
      pollIntervalSeconds = (map['pollIntervalSeconds'] as int?) ?? pollIntervalSeconds;
      persistActivityLog =
          (map['persistActivityLog'] as bool?) ?? persistActivityLog;
      conflictPolicy = ConflictPolicy.values.firstWhere(
        (p) => p.name == map['conflictPolicy'],
        orElse: () => conflictPolicy,
      );
      if (saveDir.isEmpty) saveDir = _defaultSaveDir();
    } catch (_) {
      saveDir = _defaultSaveDir();
    }
    AdbClient.instance.adbExecutable = adbPath;
    _loaded = true;
    notifyListeners();
  }

  static String _defaultSaveDir() => AppDirs.defaultSaveDir;

  Future<void> save() async {
    try {
      final f = _file ??= _configFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'saveDir': saveDir,
        'adbPath': adbPath,
        'autoConnect': autoConnect,
        'lastDeviceAddress': lastDeviceAddress,
        'scanAddresses': scanAddresses,
        'phonePaths': phonePaths,
        'pcFavorites': pcFavorites,
        'pollIntervalSeconds': pollIntervalSeconds,
        'persistActivityLog': persistActivityLog,
        'conflictPolicy': conflictPolicy.name,
      }));
    } catch (_) {}
    notifyListeners();
  }

  // ------------------------------------------------------------- mutators

  void setSaveDir(String dir) {
    if (dir == saveDir) return;
    saveDir = dir;
    save();
  }

  void setAdbPath(String path) {
    if (path == adbPath) return;
    adbPath = path;
    AdbClient.instance.adbExecutable = path;
    save();
  }

  void setAutoConnect(bool v) {
    if (v == autoConnect) return;
    autoConnect = v;
    save();
  }

  void setPollIntervalSeconds(int s) {
    final v = s.clamp(2, 60);
    if (v == pollIntervalSeconds) return;
    pollIntervalSeconds = v;
    save();
  }

  void setConflictPolicy(ConflictPolicy policy) {
    if (policy == conflictPolicy) return;
    conflictPolicy = policy;
    save();
  }

  void setPersistActivityLog(bool v) {
    if (v == persistActivityLog) return;
    persistActivityLog = v;
    save();
  }

  void setScanAddresses(List<String> list) {
    scanAddresses = List.unmodifiable(list);
    save();
  }

  void setLastDeviceAddress(String? addr) {
    if (addr == lastDeviceAddress) return;
    lastDeviceAddress = addr;
    save();
  }

  void setPhonePaths(List<String> paths) {
    phonePaths = List.unmodifiable(paths);
    save();
  }

  void addPhonePath(String path) {
    if (path.isEmpty || phonePaths.contains(path)) return;
    phonePaths = [...phonePaths, path];
    save();
  }

  void removePhonePath(String path) {
    phonePaths = phonePaths.where((p) => p != path).toList();
    save();
  }

  void addPcFavorite(String name) {
    if (name.isEmpty || pcFavorites.contains(name)) return;
    pcFavorites = [...pcFavorites, name];
    save();
  }

  void removePcFavorite(String name) {
    pcFavorites = pcFavorites.where((p) => p != name).toList();
    save();
  }
}
