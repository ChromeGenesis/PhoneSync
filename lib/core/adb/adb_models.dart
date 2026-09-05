/// Domain models shared across the ADB layer, controllers, and UI.
library;

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

enum ConnectionStatus { disconnected, connecting, connected }

enum TransferKind { pull, push }

enum TransferStatus { queued, running, done, failed, cancelled }

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
