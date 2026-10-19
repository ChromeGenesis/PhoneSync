import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/adb/adb_models.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../state/browser_controller.dart';
import '../../state/connection_controller.dart';
import '../../widgets/glass/glass_input.dart';
import '../../widgets/shared/hover_builder.dart';
import '../../widgets/shared/section_label.dart';
import '../../widgets/shared/text_style_cache.dart';
import 'wireless_pairing_card.dart';

/// Settings: connection, storage, appearance. Every mutation goes through
/// AppConfig (the SSOT) which persists immediately.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: Listenable.merge([Services.config, ConnectionController.instance]),
      builder: (context, _) {
        final config = Services.config;
        // The settings modal bounds the width; fill it naturally.
        return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              children: [
                _card(
                  context,
                  'Connection',
                  Icons.settings_input_antenna_outlined,
                  subtitle: 'How PhoneSync finds and talks to your phone',
                  children: [
                    _row(
                      context,
                      'ADB executable',
                      _editable(
                        context,
                        config.adbPath,
                        (v) => config.setAdbPath(v),
                      ),
                      hint: config.adbPath == 'adb'
                          ? 'Searching PATH and known SDK locations'
                          : config.adbPath,
                    ),
                    _row(context, 'Auto-connect on launch',
                        _toggle(context, config.autoConnect, config.setAutoConnect),
                        expand: false,
                        hint: 'Reconnect as soon as the app opens'),
                    _row(context, 'Persist activity log',
                        _toggle(context, config.persistActivityLog, (v) {
                          config.setPersistActivityLog(v);
                          Services.log.setPersistence(v);
                        }),
                        expand: false,
                        hint: 'Keeps the log across restarts'),
                    const SizedBox(height: 8),
                    const SectionLabel('Wireless scan addresses', fontSize: 10),
                    const SizedBox(height: 6),
                    ...config.scanAddresses.map((addr) => _addressRow(context, addr)),
                    _actionLink(context, Icons.add, 'Add address…', () => _addAddress(context)),
                  ],
                ),
                const SizedBox(height: 16),
                const WirelessPairingCard(),
                const SizedBox(height: 16),
                _card(
                  context,
                  'Storage',
                  Icons.folder_copy_outlined,
                  subtitle: 'Where files go, and when the phone is checked',
                  children: [
                    _row(
                      context,
                      'Pull destination',
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 380),
                            child: Text(
                              config.saveDir,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OutfitStyle.get(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () async {
                              final dir = await getDirectoryPath(
                                  initialDirectory: config.saveDir);
                              if (dir != null) config.setSaveDir(dir);
                            },
                            child: Text('Browse…',
                                style: OutfitStyle.get(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.goldPrimary)),
                          ),
                        ],
                      ),
                      expand: false,
                      hint: 'Where pulled files land',
                    ),
                    _row(context, 'Live refresh interval',
                        _intervalSelector(context, config.pollIntervalSeconds,
                            config.setPollIntervalSeconds),
                        expand: false,
                        hint: 'How often the listing re-checks the phone'),
                    _row(context, 'Push conflicts',
                        _conflictSelector(context, config.conflictPolicy,
                            config.setConflictPolicy),
                        expand: false,
                        hint: 'What to do when the phone already has a newer file'),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  context,
                  'Appearance',
                  Icons.palette_outlined,
                  children: [
                    _row(context, 'Theme mode', _themeModeSelector(context), expand: false,
                        hint: 'System follows your macOS appearance'),
                    const SizedBox(height: 6),
                    _row(context, 'Accent', _accentSelector(context), expand: false,
                        hint: 'Tints buttons, highlights and the live badge'),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  context,
                  'Saved Phone Paths',
                  Icons.bookmark_border_rounded,
                  children: [
                    ...config.phonePaths.map((p) => _savedPathRow(context, p,
                        onRemove: () => config.removePhonePath(p))),
                    _actionLink(context, Icons.add, 'Add path…',
                        () => _addPathDialog(context, config.addPhonePath)),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  context,
                  'About',
                  Icons.info_outline,
                  children: [
                    Text(
                      'PhoneSync v1.0 — wireless phone ↔ PC file sync over ADB.\n'
                      'Streaming listings, byte-level pull progress, and a live activity log.',
                      style: OutfitStyle.get(
                          fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Device: ${ConnectionController.instance.deviceLabel}',
                      style: OutfitStyle.get(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: colors.textMuted),
                    ),
                  ],
                ),
              ],
            );
      },
    );
  }

  // ------------------------------------------------------------- building

  Widget _card(BuildContext context, String title, IconData icon,
      {required List<Widget> children, String? subtitle}) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.goldPrimary.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: colors.goldPrimary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: OutfitStyle.get(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: OutfitStyle.get(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: colors.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Hairline under the header: separates the section title from a long
          // run of identical rows without boxing each one.
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 14),
            child: Divider(height: 1, color: colors.border.withAlpha(35)),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, Widget control,
      {bool expand = true, String? hint}) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: OutfitStyle.get(
                      fontSize: 12, fontWeight: FontWeight.w600, color: colors.textSecondary),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: OutfitStyle.get(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            // Compact controls (toggles, chip groups) anchor right instead of
            // stretching — a stretched switch reads as a progress bar.
            child: expand
                ? Align(alignment: Alignment.centerLeft, child: control)
                : Align(alignment: Alignment.centerRight, child: control),
          ),
        ],
      ),
    );
  }

  Widget _intervalSelector(
      BuildContext context, int current, ValueChanged<int> onChanged) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in const [3, 5, 10, 30])
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () {
                onChanged(s);
                // Re-arm the live poll so the new interval takes effect now.
                BrowserController.instance.startPolling();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: current == s
                      ? colors.goldPrimary.withAlpha(45)
                      : colors.surface.withAlpha(90),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: current == s
                          ? colors.goldPrimary
                          : colors.border.withAlpha(50)),
                ),
                child: Text(
                  '${s}s',
                  style: OutfitStyle.get(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: current == s ? colors.textGold : colors.textSecondary),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _conflictSelector(
    BuildContext context, ConflictPolicy current, ValueChanged<ConflictPolicy> onChanged) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in ConflictPolicy.values)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: current == p
                      ? colors.goldPrimary.withAlpha(45)
                      : colors.surface.withAlpha(90),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: current == p
                          ? colors.goldPrimary
                          : colors.border.withAlpha(50)),
                ),
                child: Text(
                  p.label,
                  style: OutfitStyle.get(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: current == p ? colors.textGold : colors.textSecondary),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _toggle(BuildContext context, bool value, ValueChanged<bool> onChanged) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? colors.goldPrimary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: value ? colors.goldPrimary : colors.border.withAlpha(60)),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: value ? Colors.black : colors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _editable(BuildContext context, String initial, ValueChanged<String> onSaved) {
    final controller = TextEditingController(text: initial);
    return TextField(
      controller: controller,
      onSubmitted: onSaved,
      style: OutfitStyle.get(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
      decoration: glassInputDecoration(
        context: context,
        hintText: 'adb (must be on PATH)',
      ).copyWith(
        suffixIcon: IconButton(
          icon: Icon(Icons.check_rounded, size: 16, color: context.colors.goldPrimary),
          onPressed: () => onSaved(controller.text.trim()),
        ),
      ),
    );
  }

  Widget _themeModeSelector(BuildContext context) {
    final colors = context.colors;
    final service = AppThemeService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        return Row(
          children: [
            for (final (mode, label) in [
              // System first: it is the default, so it is what most people
              // keep, and the order should say so.
              (ThemeMode.system, 'System'),
              (ThemeMode.light, 'Light'),
              (ThemeMode.dark, 'Dark'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => service.setThemeMode(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: service.themeMode == mode
                          ? colors.goldPrimary
                          : colors.surface.withAlpha(90),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: service.themeMode == mode
                              ? colors.goldPrimary
                              : colors.border.withAlpha(50)),
                    ),
                    child: Text(
                      label,
                      style: OutfitStyle.get(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: service.themeMode == mode ? Colors.black : colors.textSecondary),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _accentSelector(BuildContext context) {
    final service = AppThemeService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        return Row(
          children: [
            for (final preset in AccentPreset.all)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => service.setAccent(preset),
                  child: HoverBuilder(
                    builder: (context, hovered) => AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? preset.darkPrimary.withAlpha(
                                service.accent == preset ? 60 : (hovered ? 35 : 18))
                            : preset.lightPrimary.withAlpha(
                                service.accent == preset ? 40 : (hovered ? 28 : 14)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.isDark ? preset.darkPrimary : preset.lightPrimary,
                          width: service.accent == preset ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: context.isDark
                                  ? preset.darkPrimary
                                  : preset.lightPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            preset.label,
                            style: OutfitStyle.get(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: context.colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _addressRow(BuildContext context, String addr) {
    final colors = context.colors;
    final config = Services.config;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.lan_outlined, size: 14, color: colors.textMuted),
          const SizedBox(width: 8),
          Text(
            addr,
            style: FiraCodeStyle.get(fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.textSecondary),
          ),
          const Spacer(),
          InkWell(
            onTap: () => config.setScanAddresses(
                config.scanAddresses.where((a) => a != addr).toList()),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 13, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedPathRow(BuildContext context, String path, {required VoidCallback onRemove}) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 14, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              style: FiraCodeStyle.get(
                  fontSize: 11.5, fontWeight: FontWeight.w500, color: colors.textSecondary),
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 13, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionLink(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 14, color: colors.goldPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: OutfitStyle.get(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: colors.goldPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAddress(BuildContext context) async {
    final controller = TextEditingController(text: '192.168.0.');
    final addr = await _textDialog(context, 'Add scan address',
        'host:port — e.g. 192.168.1.20:5555', controller);
    if (addr != null && addr.contains(':')) {
      Services.config.setScanAddresses([...Services.config.scanAddresses, addr]);
    }
  }

  Future<void> _addPathDialog(BuildContext context, ValueChanged<String> onAdd) async {
    final controller = TextEditingController(text: '/sdcard/');
    final path = await _textDialog(context, 'Add phone path', '/sdcard/…', controller);
    if (path != null && path.startsWith('/')) onAdd(path);
  }

  Future<String?> _textDialog(
    BuildContext context,
    String title,
    String hint,
    TextEditingController controller,
  ) {
    final colors = context.colors;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: OutfitStyle.get(
                fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: FiraCodeStyle.get(fontSize: 12.5, color: colors.textPrimary),
          decoration: glassInputDecoration(context: context, hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: OutfitStyle.get(fontSize: 12, color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Add',
                style: OutfitStyle.get(
                    fontSize: 12, fontWeight: FontWeight.bold, color: colors.goldPrimary)),
          ),
        ],
      ),
    );
  }
}
