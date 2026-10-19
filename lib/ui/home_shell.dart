import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../core/log/log_service.dart';
import '../services/app_services.dart';
import '../services/theme_service.dart';
import '../state/connection_controller.dart';
import '../widgets/sanctuary_background.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/shared/text_style_cache.dart';
import 'dialogs/settings_dialog.dart';
import 'header_bar.dart';
import 'sidebar.dart';
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
    // Dropped directories are pushed as paths — adb push recurses into them.
    Services.transfers.enqueuePush([...files, ...folders], '/sdcard/Download/');
    Services.log.transfer(
      LogLevel.info,
      'Queued drag-and-drop push: ${files.length} file(s)${folders.isNotEmpty ? ' + ${folders.length} folder(s)' : ''}',
    );
    _select(ShellTab.transfers);
    showAppSnack(
      context,
      type: SnackType.success,
      title: 'Push queued',
      message:
          '${files.length} file(s)${folders.isNotEmpty ? ' + ${folders.length} folder(s)' : ''} → /sdcard/Download',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Wrapping the whole tree (rather than a focused child) is what makes the
    // shortcut fire from wherever focus happens to be — including inside a text
    // field or a dialog, which is exactly when people reach for Cmd+S.
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            const _OpenSettingsIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            const _OpenSettingsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) {
              if (!mounted) return null;
              showSettingsDialog(context);
              return null;
            },
          ),
        },
        child: Scaffold(
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
                          onDragEntered: (_) =>
                              setState(() => _dragging = true),
                          onDragExited: (_) =>
                              setState(() => _dragging = false),
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
                                          color: colors.goldPrimary.withAlpha(
                                            160,
                                          ),
                                          width: 2,
                                          strokeAlign:
                                              BorderSide.strokeAlignInside,
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
        ),
      ),
    );
  }
}

/// Intent for the Cmd/Ctrl+S shortcut. Distinct type so it cannot collide with
/// any other keyboard action added later.
class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}
