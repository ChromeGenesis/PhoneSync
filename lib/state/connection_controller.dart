import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/adb/adb_models.dart';
import '../core/log/log_service.dart';
import '../services/app_services.dart';

/// SSOT for device connection state. Owns auto-connect, the wireless scan,
/// and the keep-alive watchdog that detects silent disconnects.
class ConnectionController extends ChangeNotifier {
  ConnectionController._();
  static final ConnectionController instance = ConnectionController._();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  AdbDevice? _device;
  Timer? _watchdog;
  bool _scanning = false;

  ConnectionStatus get status => _status;
  AdbDevice? get device => _device;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isScanning => _scanning;
  String get deviceLabel => _device?.label ?? 'No device';
  String get addressLabel => _device?.id ?? '—';

  /// Why the adb binary could not be located, when that's the blocker.
  String? get adbFailure => Services.adb.adbResolveFailure;

  /// Try stored address, then configured scan list, then USB.
  Future<void> autoConnect() async {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      return;
    }
    final cfg = Services.config;
    final log = Services.log;

    log.connection(LogLevel.info,
        'Auto-connect starting (adb: ${cfg.adbPath})…');

    // 0. Bail out loudly if adb isn't even spawnable — otherwise every call
    // below returns empty and the scan reports a misleading "no device".
    if (!_ensureAdbAvailable()) return;

    _setStatus(ConnectionStatus.connecting);

    // 1. Already-plugged USB / stale wireless entry in `adb devices`.
    var devices = await Services.adb.listDevices();
    if (devices.isNotEmpty) {
      await _adopt(devices.first, reason: 'already authorized');
      return;
    }

    // 2. Last known wireless address first.
    final last = cfg.lastDeviceAddress;
    if (last != null && last.isNotEmpty) {
      log.connection(LogLevel.info, 'Trying last address $last…');
      if (await Services.adb.connect(last)) {
        devices = await Services.adb.listDevices();
        final match = devices.where((d) => d.id == last).firstOrNull;
        if (match != null) {
          await _adopt(match, reason: 'reconnected to $last');
          return;
        }
      }
      log.connection(LogLevel.warning, 'Last address $last unreachable');
    }

    // 3. Scan the configured candidates concurrently.
    await _scan();
  }

  /// Returns false (and parks the app in [ConnectionStatus.adbMissing]) when
  /// the adb binary is unusable. Without this the missing binary is reported
  /// as "no device reachable", which sends the user hunting the wrong problem.
  bool _ensureAdbAvailable() {
    final reason = Services.adb.adbResolveFailure;
    if (reason == null) return true;
    Services.log.connection(LogLevel.error,
        '$reason — set an absolute path in Settings → ADB executable '
        '(macOS: /usr/local/bin/adb, or ~/Library/Android/sdk/platform-tools/adb)');
    _device = null;
    _setStatus(ConnectionStatus.adbMissing);
    return false;
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    notifyListeners();
    final cfg = Services.config;
    final log = Services.log;
    log.connection(LogLevel.info,
        'Scanning ${cfg.scanAddresses.length} wireless candidate(s): ${cfg.scanAddresses.join(', ')}');
    try {
      final results = await Future.wait(cfg.scanAddresses.map((addr) async {
        final ok = await Services.adb.connect(addr);
        return MapEntry(addr, ok);
      }));
      final hit = results.where((e) => e.value).map((e) => e.key).firstOrNull;
      if (hit != null) {
        final devices = await Services.adb.listDevices();
        final match = devices.where((d) => d.id == hit).firstOrNull;
        if (match != null) {
          await _adopt(match, reason: 'found at $hit');
          return;
        }
      }
      log.connection(LogLevel.error, 'No device reachable — check Wi-Fi ADB is enabled and the address list is current');
      _setStatus(ConnectionStatus.disconnected);
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> rescan() async {
    if (_status == ConnectionStatus.connected) return;
    // Also the retry path out of adbMissing — the user may have just corrected
    // the executable path in Settings, which invalidates the resolver cache.
    if (!_ensureAdbAvailable()) return;
    _setStatus(ConnectionStatus.connecting);
    final devices = await Services.adb.listDevices();
    if (devices.isNotEmpty) {
      await _adopt(devices.first, reason: 'already authorized');
      return;
    }
    await _scan();
  }

  Future<void> _adopt(AdbDevice device, {required String reason}) async {
    if (device.model.isEmpty) {
      final model = await Services.adb.deviceModel(device.id);
      _device = AdbDevice(id: device.id, model: model ?? device.id, isWireless: device.isWireless);
    } else {
      _device = device;
    }
    _setStatus(ConnectionStatus.connected);
    if (device.isWireless) {
      Services.config.setLastDeviceAddress(device.id);
    }
    Services.log.connection(
        LogLevel.success, 'Connected — ${_device!.label} (${device.isWireless ? 'Wi-Fi ${device.id}' : 'USB ${device.id}'}) · $reason');
    _startWatchdog();
  }

  Future<void> disconnect() async {
    _stopWatchdog();
    final dev = _device;
    if (dev != null && dev.isWireless) {
      await Services.adb.disconnect(dev.id);
    }
    _device = null;
    _setStatus(ConnectionStatus.disconnected);
    Services.log.connection(LogLevel.info, 'Disconnected by user');
  }

  /// Light `adb devices` poll — catches unplugged USB and dropped Wi-Fi.
  /// While disconnected, retries silently every ~30s when auto-connect is on.
  int _reconnectTicks = 0;

  void _startWatchdog() {
    _stopWatchdog();
    _watchdog = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_status == ConnectionStatus.connected) {
        final devices = await Services.adb.listDevices();
        final id = _device?.id;
        final still = devices.any((d) => d.id == id);
        if (!still) {
          _device = null;
          _setStatus(ConnectionStatus.disconnected);
          Services.log.connection(LogLevel.warning, 'Device lost ($id) — retrying silently');
        }
        return;
      }
      if (!Services.config.autoConnect) return;
      _reconnectTicks++;
      if (_reconnectTicks % 3 != 0) return;
      if (!_ensureAdbAvailable()) return;
      final devices = await Services.adb.listDevices();
      if (devices.isNotEmpty) {
        await _adopt(devices.first, reason: 'auto-reconnected');
        return;
      }
      final last = Services.config.lastDeviceAddress;
      if (last != null && last.isNotEmpty && await Services.adb.connect(last)) {
        final refreshed = await Services.adb.listDevices();
        final match = refreshed.where((d) => d.id == last).firstOrNull;
        if (match != null) {
          await _adopt(match, reason: 'auto-reconnected to $last');
        }
      }
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  void _setStatus(ConnectionStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopWatchdog();
    super.dispose();
  }
}
