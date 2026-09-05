/// Shared byte/date formatting for the UI layer.
library;

import '../../core/adb/adb_models.dart';

extension FormatX on int {
  String get formatBytes {
    if (this < 0) return '—';
    if (this < 1024) return '$this B';
    final kb = this / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  DateTime? get _epochDate => this == 0 ? null : epochDateTime;

  /// Calendar-month distance between [d] and [now], floored at 0.
  static int _monthsSince(DateTime d, DateTime now) {
    var m = (now.year - d.year) * 12 + now.month - d.month;
    if (now.day < d.day) m--;
    return m < 0 ? 0 : m;
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Human relative timestamp: Today/Yesterday, days, weeks, months, years.
  String get formatEpoch {
    if (this == 0) return '—';
    final d = _epochDate!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    final hm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Today $hm';
    if (diff == 1) return 'Yesterday $hm';
    if (diff < 7) return '$diff days ago $hm';
    if (diff < 28) {
      final w = diff ~/ 7;
      return w == 1 ? 'Last week $hm' : '$w weeks ago $hm';
    }
    final months = _monthsSince(d, now);
    if (months < 12) {
      return months == 1 ? '1 month ago $hm' : '$months months ago $hm';
    }
    final years = months ~/ 12;
    return years == 1 ? '1 year ago $hm' : '$years years ago $hm';
  }

  /// Date-bucket label used for "By date" grouping. Files sort newest-first,
  /// so consecutive entries share a bucket until the label changes.
  String get dateGroupLabel {
    if (this == 0) return 'Unknown date';
    final d = _epochDate!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    if (diff < 14) return 'Last week';
    if (diff < 28) return '${diff ~/ 7} weeks ago';
    final months = _monthsSince(d, now);
    if (months < 12) {
      final label = _monthNames[d.month - 1];
      return d.year == now.year ? label : '$label ${d.year}';
    }
    final years = months ~/ 12;
    return years == 1 ? 'Last year' : '$years years ago';
  }
}
