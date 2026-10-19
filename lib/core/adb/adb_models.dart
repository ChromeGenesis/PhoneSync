/// Domain models shared across the ADB layer, controllers, and UI.
library;

/// Free/total space on the phone's primary storage.
class StorageInfo {
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;

  const StorageInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
  });

  double get usedFraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0);

  String get usedLabel => _human(usedBytes);
  String get freeLabel => _human(freeBytes);
  String get totalLabel => _human(totalBytes);

  static String _human(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }
}

/// A service a device advertises over mDNS.
///
/// Wireless debugging (Android 11+) publishes two of these per device: a long-
/// lived `_adb-tls-connect` endpoint and a short-lived `_adb-tls-pairing`
/// endpoint that only appears while the "Pair device with pairing code" dialog
/// is open. Discovering them is what lets the app find a phone without the user
/// having to read an IP and port off the screen and type them in.
class MdnsService {
  final String name; // e.g. adb-R3CN50JG4KJ-iQyX0R
  final String type; // _adb-tls-connect._tcp | _adb-tls-pairing._tcp
  final String hostPort; // e.g. 192.168.0.2:40759

  const MdnsService({
    required this.name,
    required this.type,
    required this.hostPort,
  });

  bool get isPairing => type.contains('pairing');
  bool get isConnect => type.contains('connect');

  String get host => hostPort.split(':').first;
  int? get port => int.tryParse(hostPort.split(':').last);

  /// The device-ish half of the mDNS name ("R3CN50JG4KJ"), which is far more
  /// recognisable than the trailing hash.
  String get deviceLabel {
    final bare = name.replaceFirst('adb-', '');
    final dash = bare.lastIndexOf('-');
    return dash > 0 ? bare.substring(0, dash) : bare;
  }

  /// `adb mdns services` prints one tab-separated record per line, under a
  /// "List of discovered mdns services" header.
  static MdnsService? tryParse(String line) {
    final parts = line.trim().split('\t');
    if (parts.length < 3) return null;
    if (!parts[1].startsWith('_adb-')) return null;
    if (!parts[2].contains(':')) return null;
    return MdnsService(name: parts[0], type: parts[1], hostPort: parts[2]);
  }

  @override
  String toString() => '$deviceLabel ($hostPort)';
}

class AdbDevice {
  final String id; // serial or host:port
  final String model;
  final bool isWireless;

  const AdbDevice({required this.id, required this.model, required this.isWireless});

  String get label => model.isEmpty ? id : model;
}

class PhoneFile {
  final String name;
  final String path; // full path on the device
  final int size; // bytes, -1 when unknown
  final int modified; // epoch seconds, 0 when unknown
  final bool isDir;

  const PhoneFile({
    required this.name,
    required this.path,
    this.size = -1,
    this.modified = 0,
    this.isDir = false,
  });

  String get ext {
    final i = name.lastIndexOf('.');
    return (i <= 0 || i == name.length - 1) ? '' : name.substring(i + 1).toLowerCase();
  }

  bool get isImage => const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'}.contains(ext);
  bool get isVideo => const {'mp4', 'mkv', 'mov', 'avi', 'webm', '3gp'}.contains(ext);

  PhoneFile copyWith({int? size, int? modified, bool? isDir}) => PhoneFile(
        name: name,
        path: path,
        size: size ?? this.size,
        modified: modified ?? this.modified,
        isDir: isDir ?? this.isDir,
      );
}

enum ConnectionStatus {
  disconnected,

  /// The adb binary itself could not be located or spawned. Distinct from
  /// [disconnected]: the phone may be fine, the toolchain is not there.
  adbMissing,

  connecting,
  connected,
}

enum TransferKind { pull, push }

enum TransferStatus {
  queued,
  running,
  paused,
  done,
  failed,
  cancelled,
}

class TransferItem {
  final String source; // device path (pull) or local path (push)
  final String target; // local path (pull) or device path (push)
  int totalBytes;
  int sentBytes;

  TransferItem({
    required this.source,
    required this.target,
    this.totalBytes = -1,
    this.sentBytes = 0,
  });
}

class TransferJob {
  final String id;
  final TransferKind kind;
  final String label;
  final List<TransferItem> items;
  TransferStatus status;
  String? error;
  int doneItems = 0;
  final DateTime startedAt = DateTime.now();
  DateTime? finishedAt;

  TransferJob({
    required this.id,
    required this.kind,
    required this.label,
    required this.items,
    this.status = TransferStatus.queued,
    this.error,
  });

  int get totalBytes {
    var sum = 0;
    for (final it in items) {
      if (it.totalBytes > 0) sum += it.totalBytes;
    }
    return sum;
  }

  int get sentBytes {
    var sum = 0;
    for (final it in items) {
      if (it.sentBytes > 0) sum += it.sentBytes;
    }
    return sum;
  }

  int get completedItems => doneItems;
}

extension EpochX on int {
  DateTime get epochDateTime => DateTime.fromMillisecondsSinceEpoch(this * 1000);
}
