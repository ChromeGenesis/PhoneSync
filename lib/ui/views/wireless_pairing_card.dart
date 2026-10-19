import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adb/adb_models.dart';
import '../../services/theme_service.dart';
import '../../state/connection_controller.dart';
import '../../widgets/glass/glass_button.dart';
import '../../widgets/glass_snackbar.dart';
import '../../widgets/shared/text_style_cache.dart';
import '../../widgets/shared/hover_builder.dart';

/// Everything needed to get a phone onto ADB over WiFi without opening a
/// terminal: discovery, pairing, and the post-reboot TCP/IP switch.
///
/// The pairing port is discovered over mDNS rather than typed, because it is a
/// transient random number that only exists while the phone's pairing dialog is
/// open — asking anyone to read it off a screen and retype it is exactly the
/// kind of friction this app exists to remove.
class WirelessPairingCard extends StatefulWidget {
  const WirelessPairingCard({super.key});

  @override
  State<WirelessPairingCard> createState() => _WirelessPairingCardState();
}

class _WirelessPairingCardState extends State<WirelessPairingCard> {
  static const _codeLength = 6;

  final _codeController = TextEditingController();
  MdnsService? _selected;
  bool _busy = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _codeController
      ..removeListener(_onCodeChanged)
      ..dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    final digits = _codeController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != _codeController.text.length) {
      final sel = _codeController.selection;
      _codeController.text = digits;
      _codeController.selection =
          sel.baseOffset >= 0 && sel.baseOffset <= digits.length
              ? TextSelection.collapsed(offset: sel.baseOffset)
              : TextSelection.collapsed(offset: digits.length);
    }
    setState(() {});
  }

  ConnectionController get _conn => ConnectionController.instance;

  List<MdnsService> get _pairingServices =>
      _conn.discovered.where((s) => s.isPairing).toList(growable: false);

  List<MdnsService> get _connectServices =>
      _conn.discovered.where((s) => s.isConnect).toList(growable: false);

  Future<void> _scan() async {
    setState(() => _scanning = true);
    await _conn.discoverWireless();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      // Default to the first pairing endpoint when exactly one is advertised —
      // the common case is a single phone sitting next to the laptop.
      if (_selected == null && _pairingServices.isNotEmpty) {
        _selected = _pairingServices.first;
      }
    });
  }

  bool get _codeComplete => _codeController.text.length == _codeLength;

  Future<void> _pair() async {
    final service = _selected;
    if (service == null || !_codeComplete || _busy) return;
    setState(() => _busy = true);
    final error = await _conn.pairWithCode(service.hostPort, _codeController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      GlassSnackbar.show(context,
          type: SnackType.error,
          title: 'Pairing failed',
          message: error);
      return;
    }
    _codeController.clear();
    await _conn.rescan();
    if (!mounted) return;
    GlassSnackbar.show(context,
        type: SnackType.success,
        title: 'Paired',
        message: 'This Mac is now trusted by ${service.deviceLabel}.');
  }

  Future<void> _enableTcpip() async {
    if (_busy) return;
    final port = 5555;
    setState(() => _busy = true);
    final error = await _conn.enableTcpip(port);
    if (!mounted) return;
    setState(() => _busy = false);
    GlassSnackbar.show(
      context,
      type: error == null ? SnackType.success : SnackType.error,
      title: error == null ? 'TCP/IP mode on' : 'Could not switch',
      message: error ??
          'Listening on $port. This survives toggling Wireless debugging off, '
              'but not a reboot — pair again after the phone restarts.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final connected = _conn.isConnected;

    return _Section(
      title: 'Wireless Pairing',
      icon: Icons.qr_code_2_rounded,
      subtitle: 'Connect a phone over WiFi — no USB, no terminal.',
      children: [
        // ── Discovery ───────────────────────────────────────────────────────
        _Step(
          index: 1,
          title: 'Turn on Wireless debugging',
          body: 'On the phone: Developer options → Wireless debugging. '
              'It advertises itself over the network automatically.',
          trailing: GlassButton(
            label: _scanning ? 'Scanning…' : 'Scan',
            icon: const Icon(Icons.radar_rounded, size: 14),
            onPressed: _scanning ? null : _scan,
          ),
        ),
        const SizedBox(height: 12),
        _Step(
          index: 2,
          title: 'Pair this Mac',
          body: _discoveryBody(),
          trailing: _pairingServices.isEmpty ? null : _pairControls(context),
        ),
        const SizedBox(height: 12),
        _Step(
          index: 3,
          title: 'Optional — fixed port',
          body: 'Wireless debugging\'s port changes every time the toggle is '
              'switched. Switching to TCP/IP mode pins it to $defaultTcpipPort, '
              'which is what makes the address stable. Still not reboot-proof: '
              'the phone drops back to USB-only after a restart.',
          trailing: GlassButton(
            label: _busy ? 'Working…' : 'Switch to $defaultTcpipPort',
            icon: const Icon(Icons.cable_rounded, size: 14),
            isPrimary: connected && !_busy,
            onPressed: connected && !_busy ? _enableTcpip : null,
          ),
        ),
        if (!connected && !_busy) ...[
          const SizedBox(height: 12),
          _Hint(
            icon: Icons.info_outline_rounded,
            text: 'Pairing needs the phone awake and on the same WiFi network. '
                'Step 3 needs an active connection first.',
            color: colors.textMuted,
          ),
        ],
      ],
    );
  }

  String _discoveryBody() {
    final pairing = _pairingServices;
    final connecting = _connectServices;
    if (_conn.discovered.isEmpty) {
      return 'No devices found yet. Enable Wireless debugging on the phone, '
          'then hit Scan.';
    }
    if (pairing.isEmpty && connecting.isNotEmpty) {
      return 'Found ${connecting.map((s) => s.deviceLabel).join(', ')}. '
          'Already paired — hit Scan or Rescan to connect. To pair a different '
          'phone, open "Pair device with pairing code" on it first.';
    }
    if (pairing.isEmpty) return 'Waiting for a pairing code on the phone…';

    final service = _selected;
    return 'Found ${service?.deviceLabel ?? 'a device'} at ${service?.hostPort ?? ''}. '
        'On the phone tap "Pair device with pairing code" and enter the 6-digit '
        'code it shows.';
  }

  // ---------------------------------------------------------------- pieces

  Widget _pairControls(BuildContext context) {
    final pairing = _pairingServices;
    final ready = _selected != null && _codeComplete && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PairingCodeInput(
          controller: _codeController,
          enabled: !_busy && _selected != null,
          onPaste: _pasteCode,
          onSubmit: ready ? _pair : null,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            GlassButton(
              label: _busy ? 'Pairing…' : 'Pair this Mac',
              icon: const Icon(Icons.link_rounded, size: 14),
              isPrimary: ready,
              onPressed: ready ? _pair : null,
            ),
            if (pairing.length > 1) ...[
              const SizedBox(width: 10),
              _devicePicker(context, pairing),
            ],
          ],
        ),
      ],
    );
  }

  Widget _devicePicker(BuildContext context, List<MdnsService> pairing) {
    final colors = context.colors;
    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: () {
          final i = pairing.indexOf(_selected!);
          setState(() => _selected = pairing[(i + 1) % pairing.length]);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: hovered ? colors.surface.withAlpha(120) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border.withAlpha(50)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.smartphone_rounded, size: 13),
              const SizedBox(width: 6),
              Text(
                _selected?.deviceLabel ?? 'Device',
                style: OutfitStyle.get(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: colors.textSecondary),
              ),
              const SizedBox(width: 4),
              Icon(Icons.swap_horiz_rounded, size: 13, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    _codeController.text = digits.substring(0, digits.length.clamp(0, _codeLength));
  }
}

/// The visible code slots and the real text field that drives them, stacked so
/// the caret lands where the user expects.
class PairingCodeInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSubmit;
  final VoidCallback? onPaste;
  final int length;
  final bool enabled;

  const PairingCodeInput({
    super.key,
    required this.controller,
    this.onSubmit,
    this.onPaste,
    this.length = 6,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = controller.text;
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.inputBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: text.length == length ? colors.emeraldLive : colors.inputBorder,
              width: text.length == length ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Container(
                  width: 30,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant.withAlpha(90),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border.withAlpha(50)),
                  ),
                  child: Text(
                    i < text.length ? text[i] : '',
                    style: FiraCodeStyle.get(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
              if (onPaste != null) ...[
                const SizedBox(width: 10),
                GlassIconButton(
                  icon: Icons.content_paste_rounded,
                  tooltip: 'Paste code',
                  iconSize: 14,
                  size: 30,
                  onPressed: enabled ? onPaste : null,
                ),
              ],
            ],
          ),
        ),
        // Transparent, full-size field sitting on top so the system caret,
        // IME and hardware keyboard all behave normally.
        Positioned.fill(
          child: Opacity(
            opacity: 0.01,
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofocus: false,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: length,
              textAlign: TextAlign.center,
              cursorColor: Colors.transparent,
              onSubmitted: (_) => onSubmit?.call(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Numbered step container — keeps the three-stage flow legible instead of
/// three undifferentiated blocks of text.
class _Step extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final Widget? trailing;

  const _Step({
    required this.index,
    required this.title,
    required this.body,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surface.withAlpha(40),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.border.withAlpha(35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.goldPrimary.withAlpha(38),
              shape: BoxShape.circle,
              border: Border.all(color: colors.goldPrimary.withAlpha(80)),
            ),
            child: Text(
              '$index',
              style: OutfitStyle.get(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: colors.goldPrimary,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: OutfitStyle.get(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: OutfitStyle.get(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: trailing),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Hint({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: OutfitStyle.get(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Card chrome, matching the other Settings sections.
class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
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
                  children: [
                    Text(
                      title,
                      style: OutfitStyle.get(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: OutfitStyle.get(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

const int defaultTcpipPort = 5555;