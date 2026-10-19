import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/adb/adb_client.dart';
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

  // ------------------------------------------------------ wireless pairing

  /// Pairing is a slow, network-dependent operation; the Settings UI binds to
  /// this so it can disable itself and show progress.
  bool _pairing = false;
  bool get isPairing => _pairing;

  /// Devices seen on mDNS during the last [discoverWireless].
  List<MdnsService> _discovered = const [];
  List<MdnsService> get discovered => _discovered;

  /// Refreshes the list of phones advertising wireless debugging.
  Future<List<MdnsService>> discoverWireless() async {
    final services = await Services.adb.mdnsServices();
    _discovered = services;
    notifyListeners();
    return services;
  }

  /// Runs `adb pair` with the 6-digit code from the phone. Returns null on
  /// success, or a human-readable reason it failed.
  Future<String?> pairWithCode(String hostPort, String code) async {
    _pairing = true;
    notifyListeners();
    try {
      final res = await Services.adb.pair(hostPort, code.trim());
      if (res.ok && res.stdout.contains('Successfully paired')) {
        Services.log.connection(LogLevel.success, 'Paired with $hostPort');
        // Remember the endpoint we just paired with. mDNS ids carry no port and
        // are useless to `adb tcpip`, so without this the follow-up "switch to
        // 5555" step would have no address to work from.
        final addresses = Services.config.scanAddresses;
        if (!addresses.contains(hostPort)) {
          Services.config.setScanAddresses([...addresses, hostPort]);
        }
        // The pairing endpoint disappears once used; the connect one remains.
        await discoverWireless();
        return null;
      }
      final reason = _describeFailure(res, 'Pairing failed');
      Services.log.connection(LogLevel.error, 'Pairing $hostPort failed — $reason');
      return reason;
    } finally {
      _pairing = false;
      notifyListeners();
    }
  }

  /// Runs `adb tcpip <port>` against the connected device, then repoints the app
  /// at the new fixed address. Returns null on success, or a reason.
  ///
  /// This is the recovery path after a reboot, when adbd drops back to USB-only:
  /// pair again, then switch to TCP mode to get back a stable port.
  Future<String?> enableTcpip(int port) async {
    final host = lastKnownHost;
    _pairing = true;
    notifyListeners();
    try {
      // Target a specific transport when we have one — `adb tcpip` refuses to
      // pick for itself when several devices are attached.
      final device = _device;
      final target =
          device != null && !device.id.contains('.') ? device.id : null;
      final res = await Services.adb.enableTcpip(port, deviceId: target);
      if (!res.ok || !res.stdout.contains('restarting in TCP mode')) {
        final reason = _describeFailure(res, 'Could not switch to TCP mode');
        Services.log.connection(LogLevel.error, 'adb tcpip $port failed — $reason');
        return reason;
      }

      // The old transport is torn down by the restart, so give the new port a
      // moment to come up rather than reusing the dead one.
      await Future<void>.delayed(const Duration(seconds: 2));
      final target2 = '$host:$port';
      if (!await Services.adb.connect(target2)) {
        final reason = 'Switched to port $port, but the device refused to '
            'reconnect. Try pairing again.';
        Services.log.connection(LogLevel.error, reason);
        return reason;
      }
      final refreshed = await Services.adb.listDevices();
      final match = refreshed.where((d) => d.id == target2).firstOrNull;
      if (match != null) {
        await _adopt(match, reason: 'TCP/IP mode on port $port');
      }
      Services.config.setScanAddresses([
        for (final a in Services.config.scanAddresses)
          if (a.startsWith('$host:')) target2 else a,
        // Also add it when the host wasn't listed at all, so the new address
        // survives even if pairing happened on a different network.
        if (!Services.config.scanAddresses.any((a) => a.startsWith('$host:')))
          target2,
      ]);
      return null;
    } finally {
      _pairing = false;
      notifyListeners();
    }
  }

  /// Best guess at the phone's host address, for actions that need one.
  String get lastKnownHost {
    // Only accept something that actually looks like host:port. An mDNS
    // transport id ("adb-R3CN…._adb-tls-connect._tcp") has no port and would
    // otherwise be handed straight to `adb tcpip`, which then targets a device
    // name instead of an address.
    for (final candidate in <String?>[
      _device?.id,
      Services.config.lastDeviceAddress,
      ...Services.config.scanAddresses,
    ]) {
      if (candidate == null || candidate.isEmpty) continue;
      if (candidate.contains(':') && candidate.split(':').first.contains('.')) {
        return candidate.split(':').first;
      }
    }
    return '';
  }

  String _describeFailure(AdbResult res, String fallback) {
    final text = '${res.stderr}\n${res.stdout}'.trim();
    if (text.isEmpty) return fallback;
    // adb's failures are one-liners; keep the most informative line.
    return text
        .split('\n')
        .map((l) => l.trim())
        .lastWhere((l) => l.isNotEmpty, orElse: () => fallback);
  }

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
    // Pin the transport before any further command runs, so listing and
    // transfers target this device even if another transport is also visible.
    Services.adb.setTargetDevice(device.id);
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
    Services.adb.setTargetDevice(null);
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
          // Stop pinning a transport that is gone, or every later command
          // fails with "device not found" instead of falling back cleanly.
          Services.adb.setTargetDevice(null);
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
