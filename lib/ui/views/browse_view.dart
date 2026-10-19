import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../core/adb/adb_models.dart';
import '../../core/device/device_actions.dart';
import '../../core/log/log_service.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../state/browser_controller.dart';
import '../../state/connection_controller.dart';
import '../../widgets/glass/glass_search_field.dart';
import '../../widgets/glass/glass_select.dart';
import '../../widgets/glass_snackbar.dart';
import '../../widgets/shared/media_empty_state.dart';
import '../../widgets/shared/text_style_cache.dart';
import '../dialogs/file_actions.dart';
import '../format.dart';
import '../widgets/file_card.dart';

/// File browser: toolbar (search/sort/group), grouped file list, and the
/// selection footer that drives pulls.
class BrowseView extends StatefulWidget {
  const BrowseView({super.key});

  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Ported from PhoneSync_Old app.py: Enter pulls the current selection.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _search.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    if (!mounted) return false;
    // Never steal Enter from a focused text field or an open dialog.
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.widget is EditableText) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    final browser = BrowserController.instance;
    if (browser.selectedCount == 0) return false;
    _pull(context, browser.selectedFiles);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final browser = BrowserController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([
        browser,
        ConnectionController.instance,
        Services.config,
      ]),
      builder: (context, _) {
        final connected = ConnectionController.instance.isConnected;
        return Container(
          decoration: BoxDecoration(
            color: colors.surface.withAlpha(35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border.withAlpha(25)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(context, browser, connected),
              const SizedBox(height: 10),
              // Storage readout sits above the list rather than behind a menu:
              // "why is my phone full" is the usual reason to open this app.
              if (connected) ...[
                const StoragePanel(),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: !connected
                    ? _disconnectedState(context)
                    : browser.loading && browser.entries.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (browser.entries.isEmpty)
                    ? MediaEmptyState(
                        icon: Icons.folder_open_rounded,
                        title: browser.error != null
                            ? 'Could not read this folder'
                            : 'Nothing here',
                        subtitle: browser.error != null
                            ? 'The device returned an error for ${browser.location.title}.'
                            : 'This location has no files yet. Pull-to-refresh via the button above.',
                      )
                    : _list(context, browser),
              ),
              if (browser.selectedCount > 0) ...[
                const SizedBox(height: 8),
                _selectionFooter(context, browser),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _toolbar(
    BuildContext context,
    BrowserController browser,
    bool connected,
  ) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: GlassSearchField(
            controller: _search,
            hintText: 'Search ${browser.location.title}…',
            onChanged: browser.setQuery,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 158,
          child: GlassSelect<SortMode>(
            value: browser.sort,
            prefixIcon: const Icon(Icons.sort_rounded, size: 14),
            items: const [
              GlassSelectItem(value: SortMode.dateDesc, label: 'Newest first'),
              GlassSelectItem(value: SortMode.dateAsc, label: 'Oldest first'),
              GlassSelectItem(value: SortMode.nameAsc, label: 'Name A→Z'),
              GlassSelectItem(value: SortMode.nameDesc, label: 'Name Z→A'),
              GlassSelectItem(value: SortMode.sizeDesc, label: 'Largest first'),
            ],
            onChanged: (v) {
              if (v != null) browser.setSort(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 150,
          child: GlassSelect<GroupMode>(
            value: browser.group,
            prefixIcon: const Icon(Icons.group_work_outlined, size: 14),
            items: const [
              GlassSelectItem(value: GroupMode.none, label: 'No grouping'),
              GlassSelectItem(value: GroupMode.day, label: 'By date'),
              GlassSelectItem(value: GroupMode.ext, label: 'By extension'),
            ],
            onChanged: (v) {
              if (v != null) browser.setGroup(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: browser.selectedCount > 0
              ? browser.clearSelection
              : browser.selectAllVisible,
          child: Text(
            browser.selectedCount > 0 ? 'Deselect all' : 'Select all',
            style: OutfitStyle.get(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, BrowserController browser) {
    final colors = context.colors;
    final rows = browser.buildRows();

    // Two-column tile grid: consecutive file cards pair up; group headers
    // claim their own row. Slots go through ListView.builder so a selection
    // toggle only lays out the tiles actually on screen.
    final slots = <List<BrowserRow>>[];
    for (final row in rows) {
      if (row.header != null) {
        slots.add([row]);
        continue;
      }
      final last = slots.isEmpty ? null : slots.last;
      if (last != null && last.length == 1 && last.first.header == null) {
        last.add(row);
      } else {
        slots.add([row]);
      }
    }
    final hasMore = _remaining(browser) > 0;

    return ListView.builder(
      itemCount: slots.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == slots.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: browser.loadMore,
                child: Text(
                  'Load ${_remaining(browser)} more…',
                  style: OutfitStyle.get(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.goldPrimary,
                  ),
                ),
              ),
            ),
          );
        }
        final slot = slots[i];
        if (slot.first.header != null) {
          return _groupHeader(
            context,
            slot.first.header!,
            slot.first.headerCount ?? 0,
          );
        }
        // IntrinsicHeight equalizes both tiles' card heights; ListView alone
        // gives unbounded height, which breaks stretch/Expanded sizing.
        return IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: FileCard(file: slot[0].file!)),
              const SizedBox(width: 12),
              Expanded(
                child: slot.length > 1
                    ? FileCard(file: slot[1].file!)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Plain group label above each section — no band or container chrome.
  Widget _groupHeader(BuildContext context, String title, int count) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: OutfitStyle.get(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: OutfitStyle.get(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  static int _remaining(BrowserController browser) {
    final total = browser.entries.length;
    return (total - browser.visibleCount).clamp(0, total);
  }

  Widget _disconnectedState(BuildContext context) {
    final colors = context.colors;
    final connection = ConnectionController.instance;
    final connecting = connection.status == ConnectionStatus.connecting;
    final adbGone = connection.status == ConnectionStatus.adbMissing;

    final title = connecting
        ? 'Searching for your phone…'
        : adbGone
            ? 'adb not found'
            : 'No device connected';
    final subtitle = connecting
        ? 'Scanning wireless ADB and USB.'
        : adbGone
            ? connection.adbFailure ?? 'The adb binary could not be located.'
            : 'Enable wireless debugging or plug in via USB, then rescan.';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            adbGone ? Icons.build_circle_outlined : Icons.phonelink_off_rounded,
            size: 46,
            color: colors.textSecondary.withAlpha(75),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: OutfitStyle.get(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: OutfitStyle.get(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          if (connection.status == ConnectionStatus.disconnected ||
              connection.status == ConnectionStatus.adbMissing)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.goldPrimary,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                await connection.rescan();
                if (connection.isConnected) {
                  await BrowserController.instance.loadDeviceFolders();
                  await BrowserController.instance.openLocation(
                    BrowseLocation.recents,
                    force: true,
                  );
                  BrowserController.instance.startPolling();
                }
              },
              label: const Text('Rescan'),
            ),
        ],
      ),
    );
  }

  Widget _selectionFooter(BuildContext context, BrowserController browser) {
    final colors = context.colors;
    final selected = browser.selectedFiles;
    final totalBytes = selected.fold<int>(
      0,
      (s, f) => s + (f.size > 0 ? f.size : 0),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.goldPrimary.withAlpha(24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.goldPrimary.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rounded, size: 17, color: colors.goldPrimary),
          const SizedBox(width: 9),
          Text(
            '${selected.length} selected · ${totalBytes.formatBytes}',
            style: OutfitStyle.get(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _pickDestination,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border.withAlpha(50)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 13,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      Services.config.saveDir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OutfitStyle.get(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Bulk quick actions for the current selection.
          if (selected.length == 1) ...[
            _bulkAction(
              context,
              icon: Icons.open_in_new_rounded,
              tooltip: 'Open on phone',
              onTap: () => _bulkSingle(context, selected.first,
                  (f) => DeviceActions.instance.open(f), 'Opened on phone'),
            ),
            _bulkAction(
              context,
              icon: Icons.ios_share_rounded,
              tooltip: 'Share…',
              onTap: () => _bulkSingle(context, selected.first,
                  (f) => DeviceActions.instance.share(f), 'Share sheet opened'),
            ),
            const SizedBox(width: 6),
          ],
          _bulkAction(
            context,
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete from phone',
            danger: true,
            onTap: () => _bulkDelete(context, selected),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: browser.clearSelection,
            child: Text(
              'Clear',
              style: OutfitStyle.get(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colors.goldPrimary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: selected.isEmpty ? null : () => _pull(context, selected),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: Text(
              'Pull to Computer',
              style: OutfitStyle.get(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDestination() async {
    final dir = await getDirectoryPath(
      initialDirectory: Services.config.saveDir,
    );
    if (dir != null) Services.config.setSaveDir(dir);
  }

  Widget _bulkAction(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final colors = context.colors;
    final tint = danger ? colors.roseDanger : colors.textSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: danger
            ? colors.roseDanger.withAlpha(24)
            : colors.surface.withAlpha(120),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: danger
                    ? colors.roseDanger.withAlpha(70)
                    : colors.border.withAlpha(60),
              ),
            ),
            child: Icon(icon, size: 16, color: tint),
          ),
        ),
      ),
    );
  }

  Future<void> _bulkSingle(
    BuildContext context,
    PhoneFile file,
    Future<bool> Function(PhoneFile) action,
    String okTitle,
  ) async {
    final ok = await action(file);
    if (!context.mounted) return;
    BrowserController.instance.clearSelection();
    showAppSnack(
      context,
      type: ok ? SnackType.success : SnackType.error,
      title: ok ? okTitle : 'Action failed',
      message: file.name,
    );
  }

  Future<void> _bulkDelete(BuildContext context, List<PhoneFile> selected) async {
    final confirmed = await confirmDelete(context, selected);
    if (confirmed != true || !context.mounted) return;
    final removed = await DeviceActions.instance.delete(selected);
    if (!context.mounted) return;
    BrowserController.instance.clearSelection();
    showAppSnack(
      context,
      type: removed > 0 ? SnackType.success : SnackType.error,
      title: removed > 0 ? 'Deleted $removed file${removed == 1 ? '' : 's'}' : 'Delete failed',
      message: removed > 0 ? 'Removed from the phone' : 'Nothing was removed',
    );
  }

  void _pull(BuildContext context, List<PhoneFile> selected) {
    final dest = Services.config.saveDir;
    Services.transfers.enqueuePull(selected, dest);
    BrowserController.instance.clearSelection();
    Services.log.transfer(
      LogLevel.info,
      'Queued pull of ${selected.length} file(s) → $dest',
    );
    showAppSnack(
      context,
      type: SnackType.info,
      title: 'Pull queued',
      message: '${selected.length} file(s) → $dest',
    );
  }
}
