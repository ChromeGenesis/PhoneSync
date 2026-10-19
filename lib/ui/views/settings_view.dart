import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/adb/adb_models.dart';
import '../../core/config/app_config.dart';
import '../../core/log/log_service.dart';
import '../../services/app_services.dart';
import '../../services/theme_service.dart';
import '../../state/browser_controller.dart';
import '../../state/connection_controller.dart';
import '../../widgets/glass/glass_input.dart';
import '../../widgets/glass/glass_search_field.dart';
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
        _Section.connection => 'How PhoneSync finds your phone, and finds adb',
        _Section.pairing => 'Connect over WiFi without a cable or a terminal',
        _Section.storage => 'Where files land, and how the phone is polled',
        _Section.appearance => 'Theme and accent',
        _Section.paths => 'Folders pinned to the sidebar',
        _Section.about => 'Version, device, and this session',
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

/// Settings: search, a section rail, and a stacked-content panel.
///
/// Edits are staged rather than applied on change. That is what makes the
/// footer's Cancel meaningful — before this, every toggle wrote straight to
/// config, so dismissing the dialog still kept whatever you touched, which is
/// the behaviour people already distrust in Settings dialogs.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  _Section _section = _Section.connection;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Draft. Null means "unchanged". ──────────────────────────────────────
  String? _adbPath;
  bool? _autoConnect;
  bool? _persistLog;
  String? _saveDir;
  int? _pollSeconds;
  ConflictPolicy? _conflict;
  ThemeMode? _themeMode;
  AccentPreset? _accent;
  List<String>? _scanAddresses;
  List<String>? _phonePaths;

  AppConfig get _cfg => Services.config;

  bool get _dirty =>
      _adbPath != null ||
      _autoConnect != null ||
      _persistLog != null ||
      _saveDir != null ||
      _pollSeconds != null ||
      _conflict != null ||
      _themeMode != null ||
      _accent != null ||
      _scanAddresses != null ||
      _phonePaths != null;

  String get _adb => _adbPath ?? _cfg.adbPath;
  bool get _auto => _autoConnect ?? _cfg.autoConnect;
  bool get _persist => _persistLog ?? _cfg.persistActivityLog;
  String get _dest => _saveDir ?? _cfg.saveDir;
  int get _poll => _pollSeconds ?? _cfg.pollIntervalSeconds;
  ConflictPolicy get _conflictPolicy => _conflict ?? _cfg.conflictPolicy;
  List<String> get _addresses => _scanAddresses ?? _cfg.scanAddresses;
  List<String> get _paths => _phonePaths ?? _cfg.phonePaths;

  void _save() {
    final cfg = _cfg;
    if (_adbPath != null) cfg.setAdbPath(_adbPath!);
    if (_autoConnect != null) cfg.setAutoConnect(_autoConnect!);
    if (_persistLog != null) {
      cfg.setPersistActivityLog(_persistLog!);
      Services.log.setPersistence(_persistLog!);
    }
    if (_saveDir != null) cfg.setSaveDir(_saveDir!);
    if (_pollSeconds != null) {
      cfg.setPollIntervalSeconds(_pollSeconds!);
      BrowserController.instance.startPolling();
    }
    if (_conflict != null) cfg.setConflictPolicy(_conflict!);
    if (_themeMode != null) AppThemeService.instance.setThemeMode(_themeMode!);
    if (_accent != null) AppThemeService.instance.setAccent(_accent!);
    if (_scanAddresses != null) cfg.setScanAddresses(_scanAddresses!);
    if (_phonePaths != null) cfg.setPhonePaths(_phonePaths!);
    Services.log.app(LogLevel.info, 'Settings saved');
    Navigator.of(context).pop();
  }

  bool _matches(String label, String? hint) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return label.toLowerCase().contains(q) ||
        (hint != null && hint.toLowerCase().contains(q));
  }

  /// Sections worth showing for the current search term.
  List<_Section> get _visibleSections {
    if (_query.isEmpty) return _Section.values;
    final q = _query.toLowerCase();
    return _Section.values
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.blurb.toLowerCase().contains(q) ||
            _sectionHasMatch(s))
        .toList(growable: false);
  }

  /// True when any labelled control in [s] matches the search, so a term like
  /// "conflict" surfaces Storage even though the word is not in its title.
  bool _sectionHasMatch(_Section s) {
    if (_query.isEmpty) return false;
    return switch (s) {
      _Section.connection => [
          'ADB executable',
          'Auto-connect on launch',
          'Persist activity log',
          'Wireless scan addresses',
        ].any((l) => l.toLowerCase().contains(_query.toLowerCase())),
      _Section.storage => [
          'Pull destination',
          'Live refresh interval',
          'Push conflicts',
        ].any((l) => l.toLowerCase().contains(_query.toLowerCase())),
      _Section.appearance =>
        ['Mode', 'Accent'].any((l) => l.toLowerCase().contains(_query.toLowerCase())),
      _Section.paths => ['Pinned folders']
          .any((l) => l.toLowerCase().contains(_query.toLowerCase())),
      _Section.pairing => ['pairing', 'wireless debugging', 'tcp']
          .any((l) => l.contains(_query.toLowerCase())),
      _Section.about => ['version', 'device', 'adb']
          .any((l) => l.contains(_query.toLowerCase())),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: Listenable.merge([
        Services.config,
        ConnectionController.instance,
        AppThemeService.instance,
      ]),
      builder: (context, _) {
        final sections = _visibleSections;
        // Keep the selection valid while a search filters the rail away.
        if (!sections.contains(_section) && sections.isNotEmpty) {
          _section = sections.first;
        }
        return Column(
          children: [
            // ── Search ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: GlassSearchField(
                controller: _searchController,
                hintText: 'Search settings — connection, storage, theme…',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Divider(height: 1, color: colors.border.withAlpha(35)),
            Expanded(
              // Proportional rail: a fixed width starves the panel on a
              // narrow window, which is what made labels wrap badly.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final railWidth =
                      (constraints.maxWidth * 0.26).clamp(150.0, 220.0);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        child: SizedBox(
                          width: railWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 14),
                              for (final s in sections)
                                _railItem(context, s),
                            ],
                          ),
                        ),
                      ),
                      // Divider stops here, above the footer.
                      Container(width: 1, color: colors.border.withAlpha(45)),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                          child: _panel(context, _section),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Divider(height: 1, color: colors.border.withAlpha(35)),
            // ── Footer ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  if (_dirty)
                    Expanded(
                      child: Text(
                        'Unsaved changes',
                        style: OutfitStyle.get(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textGold,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  _footerButton(
                    context,
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _footerButton(
                    context,
                    label: 'Save Settings',
                    icon: Icons.check_rounded,
                    primary: true,
                    onPressed: _dirty ? _save : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------ rail

  Widget _railItem(BuildContext context, _Section s) {
    final colors = context.colors;
    final active = s == _section;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          onTap: () => setState(() => _section = s),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              // Outline-and-tint rather than a solid fill: a filled block at
              // this size outweighs the content it labels.
              color: active
                  ? colors.goldPrimary.withAlpha(28)
                  : hovered
                      ? colors.surface.withAlpha(110)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? colors.goldPrimary.withAlpha(190)
                    : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  s.icon,
                  size: 16,
                  color: active ? colors.goldPrimary : colors.textSecondary,
                ),
                const SizedBox(width: 12),
                // Bounded: an unbounded Text in a Row takes its intrinsic
                // width and pushes past the rail, which made section names
                // wrap onto a ragged second line.
                Expanded(
                  child: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OutfitStyle.get(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? colors.textPrimary : colors.textSecondary,
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

  // ----------------------------------------------------------------- panel

  Widget _panel(BuildContext context, _Section s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _panelRows(context, s),
    );
  }

  List<Widget> _panelRows(BuildContext context, _Section s) {
    switch (s) {
      case _Section.connection:
        return [
          if (_matches('ADB executable', 'Where the adb binary lives'))
            _field(
              context,
              'ADB executable',
              _editable(context, _adb, (v) => setState(() => _adbPath = v)),
              helper: _adbPath != null
                  ? 'Resolved to ${Services.adb.adbResolved ?? Services.adb.adbResolveFailure ?? 'pending'}'
                  : 'Searching PATH and known SDK locations',
            ),
          if (_matches('Auto-connect on launch', 'Reconnect as soon as the app opens'))
            _field(
              context,
              'Auto-connect on launch',
              _toggle(context, _auto, (v) => setState(() => _autoConnect = v)),
            ),
          if (_matches('Persist activity log', 'Keeps the log across restarts'))
            _field(
              context,
              'Persist activity log',
              _toggle(context, _persist, (v) => setState(() => _persistLog = v)),
            ),
          if (_matches('Wireless scan addresses', 'host:port candidates tried in order'))
            _field(
              context,
              'Wireless scan addresses',
              _addressesList(context),
            ),
        ];

      case _Section.pairing:
        return const [WirelessPairingCard()];

      case _Section.storage:
        return [
          if (_matches('Pull destination', 'Where pulled files land'))
            _field(
              context,
              'Pull destination',
              _destPicker(context),
            ),
          if (_matches('Live refresh interval', 'How often the listing re-checks the phone'))
            _field(
              context,
              'Live refresh interval',
              _intervalSelector(
                  context, _poll, (v) => setState(() => _pollSeconds = v)),
            ),
          if (_matches('Push conflicts', 'What to do when the phone has a newer file'))
            _field(
              context,
              'Push conflicts',
              _conflictSelector(context, _conflictPolicy,
                  (v) => setState(() => _conflict = v)),
            ),
        ];

      case _Section.appearance:
        return [
          if (_matches('Mode', 'System follows your macOS appearance'))
            _field(
              context,
              'Mode',
              _themeSelector(context, _themeMode ?? AppThemeService.instance.themeMode,
                  (v) => setState(() => _themeMode = v)),
            ),
          if (_matches('Accent', 'Tints buttons, highlights and the live badge'))
            _field(
              context,
              'Accent',
              _accentSelector(context, _accent ?? AppThemeService.instance.accent,
                  (v) => setState(() => _accent = v)),
            ),
        ];

      case _Section.paths:
        return [
          if (_matches('Pinned folders', 'Always shown in the sidebar'))
            _field(context, 'Pinned folders', _pathsList(context)),
        ];

      case _Section.about:
        return [
          _field(
            context,
            'PhoneSync',
            Text(
              'v1.0 — wireless phone ↔ PC file sync over ADB.\n'
              'Streaming listings, byte-level pull progress, live activity log.',
              style: OutfitStyle.get(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          _field(
            context,
            'This session',
            Column(
              children: [
                _kv(context, 'Device',
                    ConnectionController.instance.deviceLabel),
                _kv(context, 'Address',
                    ConnectionController.instance.addressLabel),
                _kv(context, 'adb',
                    Services.adb.adbResolved ??
                        Services.adb.adbResolveFailure ??
                        'not resolved'),
              ],
            ),
          ),
        ];
    }
  }

  Widget _kv(BuildContext context, String k, String v) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              k,
              style: OutfitStyle.get(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
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

  // --------------------------------------------------------------- controls

  /// Stacked layout: label, then control, then helper. Beats label-left here
  /// because helpers are sentence-length and a two-column row has to squeeze
  /// one of them.
  Widget _field(BuildContext context, String label, Widget control,
      {String? helper}) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: OutfitStyle.get(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          control,
          if (helper != null) ...[
            const SizedBox(height: 7),
            Text(
              helper,
              style: OutfitStyle.get(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footerButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    bool primary = false,
  }) {
    final colors = context.colors;
    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: primary
                ? (hovered ? colors.textGold : colors.goldPrimary)
                : colors.surface.withAlpha(hovered ? 140 : 90),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primary
                  ? colors.goldPrimary
                  : colors.border.withAlpha(hovered ? 90 : 55),
            ),
            boxShadow: primary && hovered
                ? [
                    BoxShadow(
                      color: colors.goldGlow,
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: primary ? Colors.black : colors.textPrimary),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: OutfitStyle.get(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: primary ? Colors.black : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context, bool value, ValueChanged<bool> onChanged) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 44,
        height: 25,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? colors.goldPrimary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: value ? colors.goldPrimary : colors.border.withAlpha(70),
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 19,
            height: 19,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: TextField(
        controller: controller,
        onSubmitted: onSaved,
        style: OutfitStyle.get(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary),
        decoration: glassInputDecoration(context: context, hintText: 'adb')
            .copyWith(
          prefixIcon: Icon(Icons.terminal_rounded,
              size: 16, color: context.colors.textSecondary),
          suffixIcon: IconButton(
            icon: Icon(Icons.check_rounded,
                size: 16, color: context.colors.goldPrimary),
            onPressed: () => onSaved(controller.text.trim()),
          ),
        ),
      ),
    );
  }

  Widget _destPicker(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () async {
          final dir = await getDirectoryPath(initialDirectory: _dest);
          if (dir != null) setState(() => _saveDir = dir);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          decoration: BoxDecoration(
            color: colors.inputBackground,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: colors.inputBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  _dest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OutfitStyle.get(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                'Browse…',
                style: OutfitStyle.get(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.goldPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressesList(BuildContext context) {
    final colors = context.colors;
    final list = _addresses;
    if (list.isEmpty) {
      return Text(
        'No addresses yet. Add one, or pair wirelessly.',
        style: OutfitStyle.get(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.textMuted,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final addr in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    addr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FiraCodeStyle.get(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _scanAddresses =
                      list.where((a) => a != addr).toList()),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child:
                        Icon(Icons.close_rounded, size: 14, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        _addLink(
          context,
          'Add address…',
          () => _prompt(
            context,
            title: 'Add scan address',
            hint: 'host:port — e.g. 192.168.1.20:5555',
            initial: '192.168.0.',
          ).then((v) {
            if (v != null && v.contains(':')) {
              setState(() => _scanAddresses = [...list, v]);
            }
          }),
        ),
      ],
    );
  }

  Widget _pathsList(BuildContext context) {
    final colors = context.colors;
    final list = _paths;
    if (list.isEmpty) {
      return Text(
        'Nothing pinned. Folders appear automatically once a device connects.',
        style: OutfitStyle.get(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.textMuted,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FiraCodeStyle.get(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _phonePaths =
                      list.where((a) => a != p).toList()),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child:
                        Icon(Icons.close_rounded, size: 14, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        _addLink(
          context,
          'Add path…',
          () => _prompt(
            context,
            title: 'Add phone path',
            hint: '/sdcard/…',
            initial: '/sdcard/',
          ).then((v) {
            if (v != null && v.startsWith('/')) {
              setState(() => _phonePaths = [...list, v]);
            }
          }),
        ),
      ],
    );
  }

  Widget _addLink(BuildContext context, String label, Future<void> Function() onTap) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 15, color: colors.goldPrimary),
            const SizedBox(width: 7),
            Text(
              label,
              style: OutfitStyle.get(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.goldPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intervalSelector(BuildContext context, int current, ValueChanged<int> onChanged) {
    final colors = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in const [3, 5, 10, 30])
          GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: current == s
                    ? colors.goldPrimary.withAlpha(45)
                    : colors.surface.withAlpha(90),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: current == s ? colors.goldPrimary : colors.border.withAlpha(55),
                ),
              ),
              child: Text(
                '${s}s',
                style: OutfitStyle.get(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: current == s ? colors.textGold : colors.textSecondary,
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
    // Wrap, not Row: labels as long as "Keep the newer phone file" cannot fit
    // on one line at a narrow width.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in ConflictPolicy.values)
          GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: current == p
                    ? colors.goldPrimary.withAlpha(45)
                    : colors.surface.withAlpha(90),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: current == p
                      ? colors.goldPrimary
                      : colors.border.withAlpha(55),
                ),
              ),
              child: Text(
                p.label,
                style: OutfitStyle.get(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: current == p ? colors.textGold : colors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _themeSelector(BuildContext context, ThemeMode current, ValueChanged<ThemeMode> onChanged) {
    final colors = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (mode, label, icon) in [
          // System first: it is the default, and the order should say so.
          (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
          (ThemeMode.light, 'Light', Icons.light_mode_rounded),
          (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
        ])
          GestureDetector(
            onTap: () => onChanged(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: current == mode
                    ? colors.goldPrimary.withAlpha(45)
                    : colors.surface.withAlpha(90),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: current == mode
                      ? colors.goldPrimary
                      : colors.border.withAlpha(55),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: current == mode
                        ? colors.textGold
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: OutfitStyle.get(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: current == mode
                          ? colors.textGold
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _accentSelector(BuildContext context, AccentPreset current, ValueChanged<AccentPreset> onChanged) {
    final colors = context.colors;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final preset in AccentPreset.all)
          GestureDetector(
            onTap: () => onChanged(preset),
            child: HoverBuilder(
              builder: (context, hovered) => AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? preset.darkPrimary.withAlpha(
                          current == preset ? 55 : (hovered ? 32 : 16))
                      : preset.lightPrimary.withAlpha(
                          current == preset ? 38 : (hovered ? 26 : 12)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: context.isDark
                        ? preset.darkPrimary
                        : preset.lightPrimary,
                    width: current == preset ? 1.8 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: context.isDark
                            ? preset.darkPrimary
                            : preset.lightPrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      preset.label,
                      style: OutfitStyle.get(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<String?> _prompt(
    BuildContext context, {
    required String title,
    required String hint,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    final colors = context.colors;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: OutfitStyle.get(
              fontSize: 16, fontWeight: FontWeight.w800, color: colors.textPrimary),
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
            child: Text('Cancel',
                style: OutfitStyle.get(fontSize: 12, color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Add',
                style: OutfitStyle.get(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colors.goldPrimary)),
          ),
        ],
      ),
    );
  }
}