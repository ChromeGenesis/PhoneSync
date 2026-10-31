import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../core/adb/adb_models.dart';
import '../core/log/log_service.dart';
import '../services/app_services.dart';
import '../services/theme_service.dart';
import '../state/browser_controller.dart';
import '../state/connection_controller.dart';
import '../widgets/sanctuary_background.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/shared/text_style_cache.dart';
import 'header_bar.dart';
import 'sidebar.dart';
import 'dialogs/text_inbox_dialog.dart';
import 'views/activity_view.dart';
import 'views/browse_view.dart';
import 'views/transfers_view.dart';

enum ShellTab { browse, transfers, activity }

/// Top-level layout: ambient background, header bar, sidebar, workspace.
/// The whole workspace accepts drag-and-dropped files/folders from Explorer
/// and queues them as pushes to the phone.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  ShellTab _tab = ShellTab.browse;
  bool _dragging = false;
  int _seenInboxEntries = 0;
  StreamSubscription<void>? _inboxChanges;

  @override
  void initState() {
    super.initState();
    // The shell is always mounted, so it is the natural place to surface
    // phone text arrivals that happen with no inbox UI open.
    _seenInboxEntries = Services.textInbox.entries.length;
    _inboxChanges = Services.textInbox.changes.listen(_onInboxChange);
  }

  @override
  void dispose() {
    _inboxChanges?.cancel();
    super.dispose();
  }

  void _onInboxChange(void event) {
    final inbox = Services.textInbox;
    final count = inbox.entries.length;
    if (count > _seenInboxEntries && mounted) {
      final latest = inbox.entries.first;
      final preview =
          latest.text.length > 80 ? '${latest.text.substring(0, 80)}…' : latest.text;
      showAppSnack(
        context,
        type: SnackType.success,
        title: 'Text received — copied to clipboard',
        message: preview,
        duration: const Duration(milliseconds: 4200),
        onTap: () => TextInboxDialog.show(context),
      );
    }
    _seenInboxEntries = count;
  }

  void _select(ShellTab t) => setState(() => _tab = t);

  void _onDragDone(DropDoneDetails details) {
    if (!ConnectionController.instance.isConnected) {
      showAppSnack(
        context,
        type: SnackType.error,
        title: 'No device connected',
        message: 'Connect the phone before pushing files.',
      );
      return;
    }
    final files = <String>[];
    final folders = <String>[];
    for (final item in details.files) {
      final p = item.path;
      if (FileSystemEntity.typeSync(p) == FileSystemEntityType.directory) {
        folders.add(p);
      } else {
        files.add(p);
      }
    }
    if (files.isEmpty && folders.isEmpty) return;
    // Land in the folder on screen rather than always Download — the drop
    // zone *is* the workspace pane, so wherever you are looking is where you
    // mean it to go. A merged or virtual view has no single folder, and
    // falls back.
    final dest = BrowserController.instance.pushTarget;
    final dropped = [...files, ...folders];
    // Dropped directories are pushed as paths — adb push recurses into them.
    Services.transfers.enqueuePush(dropped, dest);
    Services.log.transfer(
      LogLevel.info,
      'Queued drag-and-drop push of ${summarizeNames([for (final p in dropped) baseNameOf(p)])} → $dest',
    );
    _select(ShellTab.transfers);
    showAppSnack(
      context,
      type: SnackType.success,
      title: 'Push queued — ${dropped.length} item${dropped.length == 1 ? '' : 's'}',
      message:
          '${summarizeNames([for (final p in dropped) baseNameOf(p)])} → $dest',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      body: SanctuaryBackground(
        child: Column(
          children: [
            HeaderBar(activeTab: _tab, onTabSelected: _select),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebar(activeTab: _tab, onTabSelected: _select),
                  // Distinct divider between the navigation pane and the
                  // workspace pane.
                  Container(width: 1, color: colors.border.withAlpha(90)),
                  Expanded(
                    // The drop zone is exactly this pane — never the sidebar.
                    child: DropTarget(
                      onDragEntered: (_) => setState(() => _dragging = true),
                      onDragExited: (_) => setState(() => _dragging = false),
                      onDragDone: (details) {
                        setState(() => _dragging = false);
                        _onDragDone(details);
                      },
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: IndexedStack(
                              index: _tab.index,
                              children: const [
                                BrowseView(),
                                TransfersView(),
                                ActivityView(),
                              ],
                            ),
                          ),
                          if (_dragging)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  margin: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: colors.goldPrimary.withAlpha(22),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: colors.goldPrimary.withAlpha(160),
                                      width: 2,
                                      strokeAlign: BorderSide.strokeAlignInside,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.upload_rounded,
                                        size: 44,
                                        color: colors.goldPrimary,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Drop to push to phone',
                                        style: OutfitStyle.get(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
