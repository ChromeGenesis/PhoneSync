import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../core/adb/adb_client.dart';
import '../core/log/log_service.dart';
import '../services/app_services.dart';
import '../services/theme_service.dart';
import '../state/browser_controller.dart';
import '../state/connection_controller.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/shared/hover_builder.dart';
import '../widgets/shared/section_label.dart';
import '../widgets/shared/text_style_cache.dart';
import 'home_shell.dart';

/// 208px glass sidebar: browse locations, discovered phone folders, and
/// transfer actions (the old app's left rail, reorganized).
class AppSidebar extends StatelessWidget {
  final ShellTab activeTab;
  final ValueChanged<ShellTab> onTabSelected;

  const AppSidebar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final browser = BrowserController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([browser, Services.config, ConnectionController.instance]),
      builder: (context, _) {
        final connected = ConnectionController.instance.isConnected;
        return Container(
          width: 208,
          decoration: BoxDecoration(
            color: colors.surface.withAlpha(50),
            // The pane divider lives in HomeShell — no second line here.
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Browse'),
              const SizedBox(height: 6),
              // Browse locations also lift the shell back to the browse tab —
              // picking a destination from any tab must navigate there.
              _navButton(context, Icons.schedule, 'Recent Files', () {
                onTabSelected(ShellTab.browse);
                browser.openLocation(BrowseLocation.recents);
              },
                  active: browser.location.id == BrowseViewId.recents && activeTab == ShellTab.browse,
                  enabled: connected),
              _navButton(context, Icons.crop_free, 'Screenshots', () {
                onTabSelected(ShellTab.browse);
                browser.openLocation(BrowseLocation.screenshots);
              },
                  active:
                      browser.location.id == BrowseViewId.screenshots && activeTab == ShellTab.browse,
                  enabled: connected),
              _navButton(context, Icons.download, 'Downloads', () {
                onTabSelected(ShellTab.browse);
                browser.openLocation(BrowseLocation.downloads);
              },
                  active:
                      browser.location.id == BrowseViewId.downloads && activeTab == ShellTab.browse,
                  enabled: connected),
              _navButton(context, Icons.photo_camera, 'Camera', () {
                onTabSelected(ShellTab.browse);
                browser.openLocation(BrowseLocation.camera);
              },
                  active: browser.location.id == BrowseViewId.camera && activeTab == ShellTab.browse,
                  enabled: connected),
              const SizedBox(height: 14),
              const SectionLabel('Phone Folders'),
              const SizedBox(height: 6),
              Expanded(
                child: connected
                    // Bottom fade signals the folder list scrolls instead of
                    // letting the last chip collide with the section below.
                    ? ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                          stops: [0, 0.86, 1],
                        ).createShader(rect),
                        blendMode: BlendMode.dstIn,
                        child: _folderChips(context, browser),
                      )
                    : _disconnectedNote(context),
              ),
              const SizedBox(height: 8),
              // Transfers & Activity: their own distinct section, separate
              // from file navigation.
              const SectionLabel('Transfers'),
              const SizedBox(height: 6),
              _navButton(context, Icons.swap_vert, 'Transfers',
                  () => onTabSelected(ShellTab.transfers),
                  active: activeTab == ShellTab.transfers,
                  enabled: true),
              _navButton(context, Icons.article_outlined, 'Activity',
                  () => onTabSelected(ShellTab.activity),
                  active: activeTab == ShellTab.activity,
                  enabled: true),
              const SizedBox(height: 12),
              // Push actions consolidated side-by-side.
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                        context, Icons.upload_file, 'Files', () => _pushFiles(context),
                        enabled: connected),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _actionButton(
                        context, Icons.folder_copy_outlined, 'Folder', () => _pushFolder(context),
                        enabled: connected),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _actionButton(context, Icons.chat_bubble_outline, 'Send Text / Link…',
                  () => _sendText(context),
                  enabled: connected),
              const SizedBox(height: 4),
              _actionButton(
                  context, Icons.save_alt, 'Set Save Folder…', () => _pickSaveFolder(context),
                  enabled: true),
            ],
          ),
        );
      },
    );
  }

  Widget _disconnectedNote(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        'Connect a device to browse its folders.',
        style: OutfitStyle.get(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textMuted),
      ),
    );
  }

  Widget _folderChips(BuildContext context, BrowserController browser) {
    final saved = Services.config.phonePaths;
    final discovered = browser.deviceFolders;
    final entries = <(String, String)>{
      // Set-literal of records keeps labels unique across saved + discovered.
      ...discovered.map((p) => (p.split('/').last, p)),
      ...saved.map((p) => (p.split('/').where((s) => s.isNotEmpty).last, p)),
    }.toList(growable: false);
    final isFolderActive = browser.location.id == BrowseViewId.folder;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 4),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final (label, path) = entries[i];
        final active = isFolderActive && browser.location.paths.first == path;
        return _navButton(context, Icons.folder_outlined, label, () {
          onTabSelected(ShellTab.browse);
          browser.openLocation(BrowseLocation.deviceFolder(path));
        },
            active: active,
            enabled: true,
            dense: true);
      },
    );
  }

  Widget _navButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
    bool enabled = true,
    bool dense = false,
  }) {
    final colors = context.colors;
    return HoverBuilder(
      builder: (context, hovered) {
        final bg = active
            ? colors.goldPrimary
            : hovered && enabled
                ? colors.surface.withAlpha(140)
                : colors.surface.withAlpha(30);
        final fg = active
            ? Colors.black
            : enabled
                ? (hovered ? colors.textPrimary : colors.textSecondary)
                : colors.textMuted.withAlpha(120);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [BoxShadow(color: colors.goldGlow, blurRadius: 10, offset: const Offset(0, 2))]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: dense ? 6 : 9),
                child: Row(
                  children: [
                    Icon(icon, size: dense ? 14 : 16, color: fg),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OutfitStyle.get(
                          fontSize: dense ? 11.5 : 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionButton(BuildContext context, IconData icon, String label, VoidCallback onTap,
      {bool enabled = true}) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: HoverBuilder(
            builder: (context, hovered) => AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: hovered && enabled ? colors.surface.withAlpha(120) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: hovered && enabled ? colors.border.withAlpha(50) : colors.border.withAlpha(20)),
              ),
              child: Row(
                children: [
                  Icon(icon,
                      size: 15,
                      color: enabled ? colors.textSecondary : colors.textMuted.withAlpha(110)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      label,
                      style: OutfitStyle.get(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: enabled ? colors.textSecondary : colors.textMuted.withAlpha(110)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- actions

  Future<void> _pushFiles(BuildContext context) async {
    final files = await openFiles();
    if (files.isEmpty) return;
    Services.transfers
        .enqueuePush(files.map((f) => f.path).toList(), '/sdcard/Download/');
    Services.log.transfer(LogLevel.info, 'Queued push of ${files.length} file(s) → /sdcard/Download');
    if (context.mounted) {
      showAppSnack(
        context,
        type: SnackType.info,
        title: 'Push queued',
        message: '${files.length} file(s) → /sdcard/Download',
      );
    }
  }

  Future<void> _pushFolder(BuildContext context) async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    Services.transfers.enqueuePush([dir], '/sdcard/Download/');
  }

  Future<void> _sendText(BuildContext context) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Send to Phone',
            style: OutfitStyle.get(
                fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          style: OutfitStyle.get(fontSize: 13, color: context.colors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Paste a link or any text…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: OutfitStyle.get(fontSize: 12, color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Send', style: OutfitStyle.get(fontSize: 12, fontWeight: FontWeight.bold, color: context.colors.goldPrimary)),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    final isUrl = Uri.tryParse(text)?.hasScheme ?? false;
    final ok = isUrl
        ? await AdbClient.instance.openUrl(text)
        : await AdbClient.instance.sendText(text);
    Services.log.connection(
        ok ? LogLevel.success : LogLevel.error,
        '${isUrl ? 'Opened URL' : 'Sent text'} on device${ok ? '' : ' — intent failed'}');
    if (context.mounted) {
      showAppSnack(
        context,
        type: ok ? SnackType.success : SnackType.error,
        title: ok ? 'Sent to phone' : 'Send failed',
        message: isUrl ? text : (text.length > 60 ? '${text.substring(0, 60)}…' : text),
      );
    }
  }

  Future<void> _pickSaveFolder(BuildContext context) async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    Services.config.setSaveDir(dir);
    Services.log.app(LogLevel.info, 'Save folder set to $dir');
    if (context.mounted) {
      showAppSnack(
        context,
        type: SnackType.success,
        title: 'Save folder updated',
        message: dir,
      );
    }
  }
}

/// Opens a local folder in the OS file manager (used by PC favorites).
Future<void> revealInExplorer(String path) async {
  if (Platform.isWindows) {
    Process.run('explorer.exe', [path]);
  } else if (Platform.isMacOS) {
    Process.run('open', [path]);
  } else {
    Process.run('xdg-open', [path]);
  }
}
