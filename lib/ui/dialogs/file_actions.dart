import 'package:flutter/material.dart';

import '../../core/adb/adb_models.dart';
import '../../core/device/device_actions.dart';
import '../../services/theme_service.dart';
import '../../widgets/glass_snackbar.dart';
import '../../widgets/shared/glass_modal_shell.dart';
import '../../widgets/shared/text_style_cache.dart';

/// Destructive confirmations, and the quick-action menu for a device file.
///
/// Deletes and wallpaper changes both act on the phone with no undo, so they
/// go through here rather than firing from a bare icon button.
class FileActionMenu extends StatelessWidget {
  final PhoneFile file;

  const FileActionMenu({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: Icon(Icons.more_vert_rounded, size: 17, color: colors.textSecondary),
      color: colors.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border.withAlpha(70)),
      ),
      onSelected: (value) => _run(context, value),
      itemBuilder: (context) => [
        _item(Icons.open_in_new_rounded, 'Open on phone', 'open'),
        _item(Icons.ios_share_rounded, 'Share…', 'share'),
        if (file.isImage)
          _item(Icons.wallpaper_rounded, 'Set as wallpaper', 'wallpaper'),
        const PopupMenuDivider(),
        _item(Icons.delete_outline_rounded, 'Delete from phone', 'delete',
            danger: true),
      ],
    );
  }

  PopupMenuItem<String> _item(
    IconData icon,
    String label,
    String value, {
    bool danger = false,
  }) {
    final colors = context.colors;
    final tint = danger ? colors.roseDanger : colors.textPrimary;
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 10),
          Text(
            label,
            style: OutfitStyle.get(
                fontSize: 12, fontWeight: FontWeight.w600, color: tint),
          ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, String action) async {
    switch (action) {
      case 'open':
        await _report(context, DeviceActions.instance.open(file),
            'Opened on phone', 'Could not open on phone');
      case 'share':
        await _report(context, DeviceActions.instance.share(file),
            'Share sheet opened', 'Share failed');
      case 'wallpaper':
        await _report(context, DeviceActions.instance.setWallpaper(file),
            'Wallpaper set', 'Could not set wallpaper');
      case 'delete':
        final ok = await confirmDelete(context, [file]);
        if (ok == null || !context.mounted) return;
        final removed = await DeviceActions.instance.delete([file]);
        if (!context.mounted) return;
        showAppSnack(
          context,
          type: removed > 0 ? SnackType.success : SnackType.error,
          title: removed > 0 ? 'Deleted' : 'Delete failed',
          message: removed > 0 ? file.name : file.path,
        );
    }
  }

  Future<void> _report(
      BuildContext context, Future<bool> action, String okText, String errText) async {
    final ok = await action;
    if (!context.mounted) return;
    showAppSnack(
      context,
      type: ok ? SnackType.success : SnackType.error,
      title: ok ? okText : errText,
      message: file.name,
    );
  }
}

/// Asks before anything irreversible happens on the phone.
///
/// Returns true only on explicit confirmation, null on dismissal.
Future<bool?> confirmDelete(BuildContext context, List<PhoneFile> files) {
  return _confirm(
    context,
    icon: Icons.delete_outline_rounded,
    title: files.length == 1
        ? 'Delete ${files.first.name}?'
        : 'Delete ${files.length} files?',
    body: files.length == 1
        ? 'This removes it from the phone permanently. There is no undo and no '
            'recycle bin, so anything not already on this computer is gone.'
        : 'This removes ${files.length} files from the phone permanently. '
            'There is no undo and no recycle bin, so anything not already on '
            'this computer is gone.',
    confirmLabel: 'Delete',
    danger: true,
  );
}

/// Asks before replacing the phone's wallpaper.
Future<bool?> confirmWallpaper(BuildContext context, PhoneFile file) {
  return _confirm(
    context,
    icon: Icons.wallpaper_rounded,
    title: 'Set as wallpaper?',
    body: 'The phone will show this image on the home screen and lock screen, '
        'replacing whatever is there now.',
    confirmLabel: 'Set wallpaper',
  );
}

Future<bool?> _confirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String confirmLabel,
  bool danger = false,
}) {
  final colors = context.colors;
  return showDialog<bool>(
    context: context,
    builder: (context) => GlassModalShell(
      icon: Icon(icon, size: 17, color: danger ? colors.roseDanger : colors.goldPrimary),
      title: title,
      width: 420,
      body: Text(
        body,
        style: OutfitStyle.get(
            fontSize: 12.5, fontWeight: FontWeight.w500, color: colors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: OutfitStyle.get(fontSize: 12, color: colors.textSecondary)),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: OutfitStyle.get(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: danger ? colors.roseDanger : colors.goldPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Storage readout for the phone, shown as a panel rather than a dialog —
/// it is information, not a question.
class StoragePanel extends StatefulWidget {
  const StoragePanel({super.key});

  @override
  State<StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<StoragePanel> {
  StorageInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final info = await DeviceActions.instance.storage();
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withAlpha(30)),
      ),
      child: _loading
          ? Row(
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colors.goldPrimary),
                ),
                const SizedBox(width: 10),
                Text('Reading phone storage…',
                    style: OutfitStyle.get(
                        fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.textMuted)),
              ],
            )
          : _info == null
              ? Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 14, color: colors.roseDanger),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Could not read phone storage.',
                        style: OutfitStyle.get(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary),
                      ),
                    ),
                    _refresh(context),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${_info!.usedLabel} used',
                                style: OutfitStyle.get(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: colors.textPrimary),
                              ),
                              Text(
                                '  of ${_info!.totalLabel}',
                                style: OutfitStyle.get(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textMuted),
                              ),
                              const Spacer(),
                              Text(
                                '${_info!.freeLabel} free',
                                style: OutfitStyle.get(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: _info!.usedFraction > 0.9
                                        ? colors.roseDanger
                                        : colors.emeraldLive),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _info!.usedFraction,
                              minHeight: 6,
                              backgroundColor: colors.surfaceVariant.withAlpha(120),
                              valueColor: AlwaysStoppedAnimation(
                                _info!.usedFraction > 0.9
                                    ? colors.roseDanger
                                    : colors.goldPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _refresh(context),
                  ],
                ),
    );
  }

  Widget _refresh(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: _load,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(Icons.refresh_rounded, size: 15, color: colors.textSecondary),
      ),
    );
  }
}