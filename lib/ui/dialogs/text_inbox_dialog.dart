import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/log/log_service.dart';
import '../../core/text/text_inbox_service.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../widgets/glass/glass_button.dart';
import '../../widgets/glass_snackbar.dart';
import '../../widgets/shared/glass_modal_shell.dart';
import '../../widgets/shared/text_style_cache.dart';

/// Live inbox for text arriving from the phone over the adb reverse tunnel.
///
/// Opening the dialog marks everything read; the unread badge in the header is
/// the only thing that tracks arrivals while it is closed.
class TextInboxDialog extends StatefulWidget {
  const TextInboxDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
        context: context,
        builder: (_) => const TextInboxDialog(),
      ).then((_) => Services.textInbox.markAllRead());

  @override
  State<TextInboxDialog> createState() => _TextInboxDialogState();
}

class _TextInboxDialogState extends State<TextInboxDialog> {
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    // While the inbox is on screen its contents are definitionally read; the
    // notify loop terminates because markAllRead only fires on a change.
    _changes = Services.textInbox.changes.listen(
        (_) => Services.textInbox.markAllRead());
    Services.textInbox.markAllRead();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _openOnPhone() async {
    final inbox = Services.textInbox;
    final ok = await inbox.openOnPhone();
    Services.log.app(
        ok ? LogLevel.info : LogLevel.error,
        ok
            ? 'Opened paste page on the phone'
            : 'Could not open the paste page — is the device still connected?');
    if (!mounted) return;
    showAppSnack(
      context,
      type: ok ? SnackType.success : SnackType.error,
      title: ok ? 'Opened on phone' : 'Could not open the page',
      message: ok
          ? 'Paste in the box, tap Send — it lands here.'
          : 'Check the device connection and try again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return StreamBuilder<void>(
      stream: Services.textInbox.changes,
      builder: (context, _) {
        final inbox = Services.textInbox;
        return GlassModalShell(
          icon: Icon(Icons.move_to_inbox_rounded, size: 17, color: colors.goldPrimary),
          title: 'Text Inbox',
          subtitle: 'From your phone, over the adb tunnel',
          width: 540,
          maxHeight: 620,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusCard(context, inbox),
              const SizedBox(height: 12),
              Expanded(
                child: inbox.entries.isEmpty
                    ? _emptyState(context)
                    : _entryList(context, inbox),
              ),
            ],
          ),
          actions: [
            if (inbox.entries.isNotEmpty)
              GlassButton(
                label: 'Clear',
                onPressed: () => Services.textInbox.clear(),
              ),
            const SizedBox(width: 8),
            GlassButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _statusCard(BuildContext context, TextInboxService inbox) {
    final colors = context.colors;
    final live = inbox.isServing;
    final accent = live ? colors.emeraldLive : colors.roseDanger;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withAlpha(90),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.border.withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: accent.withAlpha(120), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live ? 'Receiving on 127.0.0.1:${inbox.port}' : 'Offline',
                  style: FiraCodeStyle.get(
                      fontSize: 11, fontWeight: FontWeight.w600, color: colors.textPrimary),
                ),
                if (inbox.tunnelError != null)
                  Text(
                    'Tunnel: ${inbox.tunnelError}',
                    style: OutfitStyle.get(
                        fontSize: 10.5, fontWeight: FontWeight.w500, color: colors.roseDanger),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GlassButton(
            label: 'Open on Phone',
            icon: const Icon(Icons.phonelink_ring_rounded, size: 15),
            isPrimary: true,
            onPressed: _openOnPhone,
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 40, color: colors.textMuted.withAlpha(110)),
          const SizedBox(height: 12),
          Text(
            'Nothing yet',
            style: OutfitStyle.get(
                fontSize: 14, fontWeight: FontWeight.w700, color: colors.textSecondary),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              'Tap "Open on Phone", paste into the page, and send. Text arrives here — '
              'and lands in this PC\u2019s clipboard automatically.',
              textAlign: TextAlign.center,
              style: OutfitStyle.get(
                  fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.textMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryList(BuildContext context, TextInboxService inbox) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.separated(
        itemCount: inbox.entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _EntryCard(entry: inbox.entries[i]),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final TextInboxEntry entry;

  const _EntryCard({required this.entry});

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.text));
    if (!context.mounted) return;
    showAppSnack(
      context,
      type: SnackType.success,
      title: 'Copied',
      message: entry.text.length > 60 ? '${entry.text.substring(0, 60)}…' : entry.text,
    );
  }

  String _stamp() {
    final t = entry.received;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 8, 11),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(60),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.border.withAlpha(35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _stamp(),
              style: FiraCodeStyle.get(
                  fontSize: 10, fontWeight: FontWeight.w500, color: colors.textMuted),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: SelectableText(
              entry.text,
              maxLines: 8,
              style: OutfitStyle.get(
                  fontSize: 12.5, fontWeight: FontWeight.w500, color: colors.textPrimary, height: 1.45),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              tooltip: 'Copy',
              onPressed: () => _copy(context),
              icon: Icon(Icons.copy_rounded, size: 15, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
