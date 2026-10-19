import 'package:flutter/material.dart';

import '../../core/adb/adb_models.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../widgets/shared/section_label.dart';
import '../../widgets/shared/media_empty_state.dart';
import '../../widgets/shared/text_style_cache.dart';
import '../format.dart';

/// Transfer queue: active jobs with live progress on top, finished history
/// below. Pure projection of TransferService.
class TransfersView extends StatelessWidget {
  const TransfersView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = Services.transfers;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final jobs = service.jobs;
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
                  const SectionLabel('Transfers'),
                  const Spacer(),
                  if (service.conflicts.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _ConflictBanner(
                      count: service.conflicts.length,
                      onOverwrite: () {
                        final ids = service.conflicts.map((c) => c.$1.id).toSet();
                        for (final id in ids) {
                          service.overwriteConflicts(id);
                        }
                      },
                      onKeepRemote: () {
                        final ids = service.conflicts.map((c) => c.$1.id).toSet();
                        for (final id in ids) {
                          service.keepRemoteConflicts(id);
                        }
                      },
                    ),
                  ],
                  if (service.hasPaused) ...[
                    TextButton.icon(
                      onPressed: service.resumeAll,
                      icon: const Icon(Icons.play_arrow_rounded, size: 15),
                      label: Text('Resume all',
                          style: OutfitStyle.get(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colors.emeraldLive)),
                    ),
                    TextButton.icon(
                      onPressed: service.pauseAll,
                      icon: const Icon(Icons.pause_rounded, size: 15),
                      label: Text('Pause all',
                          style: OutfitStyle.get(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary)),
                    ),
                  ],
                  if (service.retryable.isNotEmpty)
                    TextButton.icon(
                      onPressed: service.retryAllFailed,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: Text('Retry ${service.retryable.length}',
                          style: OutfitStyle.get(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colors.goldPrimary)),
                    ),
                  if (jobs.any((j) =>
                      j.status != TransferStatus.queued &&
                      j.status != TransferStatus.running &&
                      j.status != TransferStatus.paused))
                    TextButton(
                      onPressed: service.clearFinished,
                      child: Text('Clear finished',
                          style: OutfitStyle.get(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: jobs.isEmpty
                    ? const MediaEmptyState(
                        icon: Icons.swap_vert_rounded,
                        title: 'No transfers yet',
                        subtitle:
                            'Select files in Browse and pull them to your computer, or push files to the phone.',
                      )
                    : ListView.builder(
                        itemCount: jobs.length,
                        itemBuilder: (context, i) => _JobCard(job: jobs[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  final int count;
  final VoidCallback onOverwrite;
  final VoidCallback onKeepRemote;

  const _ConflictBanner({
    required this.count,
    required this.onOverwrite,
    required this.onKeepRemote,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.roseDanger.withAlpha(26),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colors.roseDanger.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: colors.roseDanger),
          const SizedBox(width: 7),
          Text(
            '$count newer on phone',
            style: OutfitStyle.get(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: colors.roseDanger),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onOverwrite,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('Overwrite',
                  style: OutfitStyle.get(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary)),
            ),
          ),
          InkWell(
            onTap: onKeepRemote,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('Keep theirs',
                  style: OutfitStyle.get(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? tint;
  final bool enabled;

  const _JobButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.tint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = !enabled
        ? colors.textMuted.withAlpha(90)
        : tint ?? colors.textSecondary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surface.withAlpha(100),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: colors.border.withAlpha(50)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final TransferJob job;
  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = Services.transfers;
    final total = job.totalBytes;
    final sent = job.sentBytes;
    final progress = total > 0 ? (sent / total).clamp(0.0, 1.0) : null;
    final itemProgress = job.items.isEmpty
        ? 0.0
        : job.doneItems / job.items.length;
    final running = job.status == TransferStatus.running;
    final paused = job.status == TransferStatus.paused;
    final pending = job.status == TransferStatus.queued || paused;
    final (statusColor, statusLabel) = switch (job.status) {
      TransferStatus.queued => (colors.textMuted, 'QUEUED'),
      TransferStatus.paused => (colors.textGold, 'PAUSED'),
      TransferStatus.running => (colors.goldPrimary, 'RUNNING'),
      TransferStatus.done => (colors.emeraldLive, 'DONE'),
      TransferStatus.failed => (colors.roseDanger, 'FAILED'),
      TransferStatus.cancelled => (colors.textMuted, 'CANCELLED'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: running
                ? colors.goldPrimary.withAlpha(90)
                : colors.border.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: (job.kind == TransferKind.pull ? colors.goldPrimary : colors.emeraldLive)
                      .withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  job.kind == TransferKind.pull
                      ? Icons.download_rounded
                      : Icons.upload_rounded,
                  size: 16,
                  color: job.kind == TransferKind.pull
                      ? colors.goldPrimary
                      : colors.emeraldLive,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OutfitStyle.get(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${job.startedAt.formatClock()}'
                      '${job.finishedAt != null ? ' → ${job.finishedAt!.formatClock()}' : ''}'
                      '  ·  ${job.doneItems}/${job.items.length} files'
                      '${total > 0 ? '  ·  ${sent.formatBytes} / ${total.formatBytes}' : ''}'
                      '${job.error != null ? '  ·  ${job.error}' : ''}',
                      style: OutfitStyle.get(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withAlpha(90)),
                ),
                child: Text(
                  statusLabel,
                  style: OutfitStyle.get(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                      letterSpacing: 0.4),
                ),
              ),
              const SizedBox(width: 8),
              _JobButton(
                icon: Icons.arrow_upward_rounded,
                tooltip: 'Move up',
                // Newest-first display: moving up means later in the list.
                onTap: () => service.move(job.id, 1),
                enabled: pending,
              ),
              _JobButton(
                icon: Icons.arrow_downward_rounded,
                tooltip: 'Move down',
                onTap: () => service.move(job.id, -1),
                enabled: pending,
              ),
              if (paused)
                _JobButton(
                  icon: Icons.play_arrow_rounded,
                  tooltip: 'Resume',
                  tint: colors.emeraldLive,
                  onTap: () => service.resume(job.id),
                )
              else if (pending)
                _JobButton(
                  icon: Icons.pause_rounded,
                  tooltip: 'Pause',
                  onTap: () => service.pause(job.id),
                ),
              if (job.status == TransferStatus.failed)
                _JobButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Retry failed items',
                  tint: colors.goldPrimary,
                  onTap: () => service.retryFailed(job.id),
                ),
              if (running) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => Services.transfers.cancel(job.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child:
                        Icon(Icons.close_rounded, size: 14, color: colors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          if (running) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress ?? itemProgress,
                minHeight: 4,
                backgroundColor: colors.border.withAlpha(30),
                valueColor: AlwaysStoppedAnimation(colors.goldPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension _ClockX on DateTime {
  String formatClock() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
}
