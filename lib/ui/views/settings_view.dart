import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/adb/adb_models.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../state/browser_controller.dart';
import '../../state/connection_controller.dart';
import '../../widgets/glass/glass_input.dart';
import '../../widgets/shared/hover_builder.dart';
import '../../widgets/shared/text_style_cache.dart';
import 'wireless_pairing_card.dart';

enum _Section { connection, pairing, storage, appearance, paths, about }

extension on _Section {
  String get title => switch (this) {
    _Section.connection => 'Connection',
    _Section.pairing => 'Pairing',
    _Section.storage => 'Storage',
    _Section.appearance => 'Appearance',
    _Section.paths => 'Phone paths',
    _Section.about => 'About',
  };

  String get blurb => switch (this) {
    _Section.connection => 'How PhoneSync finds your phone and adb itself',
    _Section.pairing => 'Connect over WiFi without a cable or a terminal',
    _Section.storage => 'Where files land, and how the phone is polled',
    _Section.appearance => 'Theme and accent',
    _Section.paths => 'Folders pinned to the sidebar',
    _Section.about => 'Version and current device',
  };

  IconData get icon => switch (this) {
    _Section.connection => Icons.settings_input_antenna_outlined,
    _Section.pairing => Icons.qr_code_2_rounded,
    _Section.storage => Icons.folder_copy_outlined,
    _Section.appearance => Icons.palette_outlined,
    _Section.paths => Icons.bookmark_border_rounded,
    _Section.about => Icons.info_outline,
  };
}

/// Settings: a two-pane layout rather than one long scroll.
///
/// The previous version stacked every control into a single column of cards,
/// which meant scrolling past four sections to reach the fifth and no sense of
/// where you were. A rail plus one panel at a time is the desktop convention
/// and it finally fits the width the modal already had.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  _Section _section = _Section.connection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: Listenable.merge([
        Services.config,
        ConnectionController.instance,
      ]),
      builder: (context, _) {
        // Proportional rail. A fixed 186px starves the panel on a narrow
        // window, which is what made labels and hints wrap badly.
        return LayoutBuilder(
          builder: (context, constraints) {
            final railWidth = (constraints.maxWidth * 0.28).clamp(132.0, 186.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: railWidth,
                  decoration: BoxDecoration(
                    color: colors.surface.withAlpha(30),
                    border: Border(
                      right: BorderSide(color: colors.border.withAlpha(45)),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in _Section.values) _railItem(context, s),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOut,
                    child: SingleChildScrollView(
                      key: ValueKey(_section),
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _panelHeader(context, _section),
                          const SizedBox(height: 18),
                          ..._content(context, _section),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _railItem(BuildContext context, _Section s) {
    final colors = context.colors;
    final active = s == _section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          onTap: () => setState(() => _section = s),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? colors.goldPrimary
                  : hovered
                  ? colors.surface.withAlpha(110)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: colors.goldGlow,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  s.icon,
                  size: 15,
                  color: active ? Colors.black : colors.textSecondary,
                ),
                const SizedBox(width: 10),
                // Bounded: an unbounded Text in a Row takes its intrinsic
                // width and pushes the row wider than the rail, which is what
                // made section names wrap onto a second, ragged line.
                Expanded(
                  child: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OutfitStyle.get(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? Colors.black : colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelHeader(BuildContext context, _Section s) {
    final colors = context.colors;
    final connected = ConnectionController.instance.isConnected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.title.toUpperCase(),
                style: OutfitStyle.get(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: colors.goldPrimary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.blurb,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: OutfitStyle.get(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // Live connection state belongs on the Connection section, where it is
        // the thing being configured — not decoration on every panel.
        if (s == _Section.connection)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (connected ? colors.emeraldLive : colors.roseDanger)
                  .withAlpha(26),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (connected ? colors.emeraldLive : colors.roseDanger)
                    .withAlpha(80),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: connected ? colors.emeraldLive : colors.roseDanger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  connected
                      ? ConnectionController.instance.deviceLabel
                      : 'Not connected',
                  style: OutfitStyle.get(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: connected ? colors.emeraldLive : colors.roseDanger,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------- content

  List<Widget> _content(BuildContext context, _Section s) {
    final config = Services.config;
    return switch (s) {
      _Section.connection => [
        _group(context, 'Device discovery', [
          _row(
            context,
            'ADB executable',
            _editable(context, config.adbPath, (v) => config.setAdbPath(v)),
            hint: config.adbPath == 'adb'
                ? 'Searching PATH and known SDK locations'
                : config.adbPath,
          ),
          _row(
            context,
            'Auto-connect on launch',
            _toggle(context, config.autoConnect, config.setAutoConnect),
            trailing: true,
            hint: 'Reconnect as soon as the app opens',
          ),
          _row(
            context,
            'Persist activity log',
            _toggle(context, config.persistActivityLog, (v) {
              config.setPersistActivityLog(v);
              Services.log.setPersistence(v);
            }),
            trailing: true,
            hint: 'Keeps the log across restarts',
          ),
        ]),
        _group(context, 'Wireless scan addresses', [
          if (config.scanAddresses.isEmpty)
            _empty(context, 'No addresses yet. Add one, or pair wirelessly.'),
          ...config.scanAddresses.map((addr) => _addressRow(context, addr)),
          _actionLink(
            context,
            Icons.add,
            'Add address…',
            () => _addAddress(context),
          ),
        ]),
      ],
      _Section.pairing => const [WirelessPairingCard()],
      _Section.storage => [
        _group(context, 'Files', [
          _row(
            context,
            'Pull destination',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    config.saveDir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OutfitStyle.get(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final dir = await getDirectoryPath(
                      initialDirectory: config.saveDir,
                    );
                    if (dir != null) config.setSaveDir(dir);
                  },
                  child: Text(
                    'Browse…',
                    style: OutfitStyle.get(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: context.colors.goldPrimary,
                    ),
                  ),
                ),
              ],
            ),
            trailing: true,
            hint: 'Where pulled files land',
          ),
        ]),
        _group(context, 'Behaviour', [
          _row(
            context,
            'Live refresh interval',
            _intervalSelector(
              context,
              config.pollIntervalSeconds,
              config.setPollIntervalSeconds,
            ),
            trailing: true,
            hint: 'How often the listing re-checks the phone',
          ),
          _row(
            context,
            'Push conflicts',
            _conflictSelector(
              context,
              config.conflictPolicy,
              config.setConflictPolicy,
            ),
            trailing: true,
            hint: 'What to do when the phone already has a newer file',
          ),
        ]),
      ],
      _Section.appearance => [
        _group(context, 'Theme', [
          _row(
            context,
            'Mode',
            _themeModeSelector(context),
            trailing: true,
            hint: 'System follows your macOS appearance',
          ),
        ]),
        _group(context, 'Accent', [_accentSelector(context)]),
      ],
      _Section.paths => [
        _group(context, 'Pinned folders', [
          if (config.phonePaths.isEmpty)
            _empty(
              context,
              'Nothing pinned. Folders show up automatically once a device is connected.',
            ),
          ...config.phonePaths.map(
            (p) => _savedPathRow(
              context,
              p,
              onRemove: () => config.removePhonePath(p),
            ),
          ),
          _actionLink(
            context,
            Icons.add,
            'Add path…',
            () => _addPathDialog(context, config.addPhonePath),
          ),
        ]),
      ],
      _Section.about => [
        _group(context, 'PhoneSync', [
          Text(
            'PhoneSync v1.0 — wireless phone ↔ PC file sync over ADB.\n'
            'Streaming listings, byte-level pull progress, and a live activity log.',
            style: OutfitStyle.get(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
            ),
          ),
        ]),
        _group(context, 'This session', [
          _kv(context, 'Device', ConnectionController.instance.deviceLabel),
          _kv(context, 'Address', ConnectionController.instance.addressLabel),
          _kv(
            context,
            'adb',
            Services.adb.adbResolved ??
                Services.adb.adbResolveFailure ??
                'not resolved',
          ),
        ]),
      ],
    };
  }

  Widget _group(BuildContext context, String title, List<Widget> children) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: OutfitStyle.get(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: colors.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: OutfitStyle.get(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: context.colors.textMuted,
      ),
    ),
  );

  Widget _kv(BuildContext context, String k, String v) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k,
              style: OutfitStyle.get(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: FiraCodeStyle.get(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- controls

  /// A labelled row. [trailing] right-aligns compact controls (toggles, chip
  /// groups) — a stretched switch reads as a progress bar.
  Widget _row(
    BuildContext context,
    String label,
    Widget control, {
    bool trailing = false,
    String? hint,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: OutfitStyle.get(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OutfitStyle.get(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 18),
          if (trailing)
            Align(alignment: Alignment.centerRight, child: control)
          else
            Flexible(child: control),
        ],
      ),
    );
  }

  Widget _intervalSelector(
    BuildContext context,
    int current,
    ValueChanged<int> onChanged,
  ) {
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: current == s
                      ? colors.goldPrimary.withAlpha(45)
                      : colors.surface.withAlpha(90),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: current == s
                        ? colors.goldPrimary
                        : colors.border.withAlpha(50),
                  ),
                ),
                child: Text(
                  '${s}s',
                  style: OutfitStyle.get(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: current == s
                        ? colors.textGold
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _conflictSelector(
    BuildContext context,
    ConflictPolicy current,
    ValueChanged<ConflictPolicy> onChanged,
  ) {
    final colors = context.colors;
    // Wrap, not Row: labels as long as "Keep the newer phone file" cannot fit
    // on one line at a narrow width.
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in ConflictPolicy.values)
          GestureDetector(
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
                      : colors.border.withAlpha(50),
                ),
              ),
              child: Text(
                p.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OutfitStyle.get(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: current == p ? colors.textGold : colors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _toggle(
    BuildContext context,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 40,
        height: 23,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? colors.goldPrimary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? colors.goldPrimary : colors.border.withAlpha(60),
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: value ? Colors.black : colors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _editable(
    BuildContext context,
    String initial,
    ValueChanged<String> onSaved,
  ) {
    final controller = TextEditingController(text: initial);
    // Flexible rather than a hard 340px cap: that cap was wider than the
    // panel at small window sizes and forced the row to reflow.
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: TextField(
          controller: controller,
          onSubmitted: onSaved,
          style: OutfitStyle.get(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
          decoration: glassInputDecoration(context: context, hintText: 'adb')
              .copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: context.colors.goldPrimary,
                  ),
                  onPressed: () => onSaved(controller.text.trim()),
                ),
              ),
        ),
      ),
    );
  }

  Widget _themeModeSelector(BuildContext context) {
    final colors = context.colors;
    final service = AppThemeService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: service.themeMode == mode
                        ? colors.goldPrimary
                        : colors.surface.withAlpha(90),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: service.themeMode == mode
                          ? colors.goldPrimary
                          : colors.border.withAlpha(50),
                    ),
                  ),
                  child: Text(
                    label,
                    style: OutfitStyle.get(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: service.themeMode == mode
                          ? Colors.black
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _accentSelector(BuildContext context) {
    final service = AppThemeService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final preset in AccentPreset.all)
            GestureDetector(
              onTap: () => service.setAccent(preset),
              child: HoverBuilder(
                builder: (context, hovered) => AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? preset.darkPrimary.withAlpha(
                            service.accent == preset ? 60 : (hovered ? 35 : 18),
                          )
                        : preset.lightPrimary.withAlpha(
                            service.accent == preset ? 40 : (hovered ? 28 : 14),
                          ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: context.isDark
                          ? preset.darkPrimary
                          : preset.lightPrimary,
                      width: service.accent == preset ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: context.isDark
                              ? preset.darkPrimary
                              : preset.lightPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        preset.label,
                        style: OutfitStyle.get(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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
            style: FiraCodeStyle.get(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: () => config.setScanAddresses(
              config.scanAddresses.where((a) => a != addr).toList(),
            ),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedPathRow(
    BuildContext context,
    String path, {
    required VoidCallback onRemove,
  }) {
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
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionLink(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
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
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: colors.goldPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- dialogs

  Future<void> _addAddress(BuildContext context) async {
    final controller = TextEditingController(text: '192.168.0.');
    final addr = await _textDialog(
      context,
      'Add scan address',
      'host:port — e.g. 192.168.1.20:5555',
      controller,
    );
    if (addr != null && addr.contains(':')) {
      Services.config.setScanAddresses([
        ...Services.config.scanAddresses,
        addr,
      ]);
    }
  }

  Future<void> _addPathDialog(
    BuildContext context,
    ValueChanged<String> onAdd,
  ) async {
    final controller = TextEditingController(text: '/sdcard/');
    final path = await _textDialog(
      context,
      'Add phone path',
      '/sdcard/…',
      controller,
    );
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
        title: Text(
          title,
          style: OutfitStyle.get(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: FiraCodeStyle.get(fontSize: 12.5, color: colors.textPrimary),
          decoration: glassInputDecoration(context: context, hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: OutfitStyle.get(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(
              'Add',
              style: OutfitStyle.get(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.goldPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
