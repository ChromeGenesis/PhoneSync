import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/log/log_service.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../widgets/glass/glass_search_field.dart';
import '../../widgets/glass/glass_chip.dart';
import '../../widgets/glass_snackbar.dart';
import '../../widgets/shared/media_empty_state.dart';
import '../../widgets/shared/section_label.dart';
import '../../widgets/shared/text_style_cache.dart';

/// Lifecycle-log view, styled after the operator console: category filter
/// chips with live counts, search, monospace event rows, copy/export.
class ActivityView extends StatefulWidget {
  const ActivityView({super.key});

  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView> {
  LogCategory? _filter;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final log = Services.log;
    return AnimatedBuilder(
      animation: log,
      builder: (context, _) {
        final events = _visibleEvents(log);
        return Container(
          decoration: BoxDecoration(
            color: colors.surface.withAlpha(35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border.withAlpha(25)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SectionLabel('Activity Log'),
                  const SizedBox(width: 8),
                  Text(
                    '${events.length} / ${log.total} events',
                    style: OutfitStyle.get(
                        fontSize: 10.5, fontWeight: FontWeight.w600, color: colors.textMuted),
                  ),
                  const Spacer(),
                  _actionButton(context, Icons.copy_rounded, 'Copy All',
                      () => _copyAll(context, log)),
                  const SizedBox(width: 8),
                  _actionButton(context, Icons.save_outlined, 'Export File',
                      () => _export(context, log)),
                  const SizedBox(width: 8),
                  _actionButton(context, Icons.delete_outline, 'Clear',
                      () => log.clear(),
                      danger: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GlassSearchField(
                      controller: _search,
                      hintText: 'Search logs…',
                      onChanged: (v) => setState(() => _query = v.toLowerCase()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  GlassChip(
                    label: 'All',
                    count: log.total,
                    isSelected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  for (final c in LogCategory.values)
                    GlassChip(
                      label: _categoryLabel(c),
                      count: log.counts[c] ?? 0,
                      isSelected: _filter == c,
                      onTap: () => setState(() => _filter = c),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: events.isEmpty
                    ? const MediaEmptyState(
                        icon: Icons.article_outlined,
                        title: 'No events',
                        subtitle:
                            'Connections, listings and transfers will appear here as they happen.',
                      )
                    : ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (context, i) {
                          final e = events[events.length - 1 - i]; // newest first
                          return _eventRow(context, e);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<LogEvent> _visibleEvents(LogService log) {
    return log.events.where((e) {
      if (_filter != null && e.category != _filter) return false;
      if (_query.isNotEmpty && !e.message.toLowerCase().contains(_query)) return false;
      return true;
    }).toList();
  }

  String _categoryLabel(LogCategory c) => switch (c) {
        LogCategory.connection => 'Connection',
        LogCategory.transfer => 'Transfer',
        LogCategory.browse => 'Browse',
        LogCategory.app => 'App',
      };

  Color _levelColor(BuildContext context, LogLevel level) {
    final colors = context.colors;
    return switch (level) {
      LogLevel.info => colors.goldPrimary,
      LogLevel.success => colors.emeraldLive,
      LogLevel.warning => colors.textGold,
      LogLevel.error => colors.roseDanger,
    };
  }

  Widget _eventRow(BuildContext context, LogEvent e) {
    final colors = context.colors;
    final levelColor = _levelColor(context, e.level);
    final t = e.ts;
    final stamp =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4.5),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: levelColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            '[$stamp]',
            style: FiraCodeStyle.get(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textMuted),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              e.message,
              style: FiraCodeStyle.get(fontSize: 11, fontWeight: FontWeight.w400, color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            e.category.name.toUpperCase(),
            style: OutfitStyle.get(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: colors.textMuted.withAlpha(160),
                letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final colors = context.colors;
    final tint = danger ? colors.roseDanger : colors.textPrimary;
    return Material(
      color: colors.surface.withAlpha(120),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border.withAlpha(45)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 6),
              Text(
                label,
                style: OutfitStyle.get(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: tint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyAll(BuildContext context, LogService log) async {
    await Clipboard.setData(ClipboardData(text: log.exportText(category: _filter)));
    if (context.mounted) {
      GlassSnackbar.show(
        context,
        type: SnackType.success,
        title: 'Copied',
        message: '${_visibleEvents(log).length} log events on the clipboard',
      );
    }
  }

  Future<void> _export(BuildContext context, LogService log) async {
    final f = await log.exportToFile(Services.config.saveDir, category: _filter);
    if (context.mounted) {
      GlassSnackbar.show(
        context,
        type: f != null ? SnackType.success : SnackType.error,
        title: f != null ? 'Log exported' : 'Export failed',
        message: f?.path ?? 'Could not write the log file.',
      );
    }
    if (f != null) Services.log.app(LogLevel.info, 'Exported log → ${f.path}');
  }
}
