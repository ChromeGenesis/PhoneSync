import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../adb/adb_client.dart';

/// Single source of truth for every persisted setting.
///
/// Stored as JSON in the user's config dir; controllers mutate through the
/// typed setters which persist automatically.
class AppConfig extends ChangeNotifier {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  static const _appName = 'PhoneSync';

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

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Config file location: %APPDATA%/PhoneSync on Windows, else ~/.config.
  static File _configFile() {
    final env = Platform.environment;
    String base;
    if (env['APPDATA'] != null && env['APPDATA']!.isNotEmpty) {
      base = '${env['APPDATA']}${Platform.pathSeparator}$_appName';
    } else if (env['HOME'] != null) {
      base = '${env['HOME']}${Platform.pathSeparator}.config${Platform.pathSeparator}$_appName';
    } else {
      base = Directory.systemTemp.path;
    }
    return File('$base${Platform.pathSeparator}config.json');
  }

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
      if (saveDir.isEmpty) saveDir = _defaultSaveDir();
    } catch (_) {
      saveDir = _defaultSaveDir();
    }
    AdbClient.instance.adbExecutable = adbPath;
    _loaded = true;
    notifyListeners();
  }

  static String _defaultSaveDir() {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    return '$home${Platform.pathSeparator}Downloads';
  }

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

  void setScanAddresses(List<String> list) {
    scanAddresses = List.unmodifiable(list);
    save();
  }

  void setLastDeviceAddress(String? addr) {
    if (addr == lastDeviceAddress) return;
    lastDeviceAddress = addr;
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
