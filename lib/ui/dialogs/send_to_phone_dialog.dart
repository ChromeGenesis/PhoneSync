import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adb/adb_client.dart';
import '../../services/theme_service.dart';
import '../../widgets/glass/glass_button.dart';
import '../../widgets/shared/glass_modal_shell.dart';
import '../../widgets/shared/text_style_cache.dart';

/// Which intent a payload should be delivered through.
enum SendMode {
  text('Text', Icons.chat_bubble_outline_rounded),
  link('Link', Icons.link_rounded);

  const SendMode(this.label, this.icon);
  final String label;
  final IconData icon;

  String get blurb => this == SendMode.text
      ? 'Shared as text — your phone offers apps that accept it.'
      : 'Opened directly in your browser.';
}

/// Outcome of a send. Returned to the caller rather than snackbar'd from in
/// here: this dialog's context is dead the moment it pops, and the snackbar
/// helper (correctly) refuses an unmounted context — so whoever opened the
/// dialog owns the confirmation.
class SendResult {
  final bool ok;
  final String payload;

  const SendResult({required this.ok, required this.payload});
}

/// Replaces the old bare `AlertDialog` + raw `TextField`.
///
/// Two things were missing and both mattered: the caller had no idea whether a
/// paste would arrive as text or launch a URL (it silently auto-detected), and
/// there was no way in to the clipboard without leaving the keyboard.
class SendToPhoneDialog extends StatefulWidget {
  const SendToPhoneDialog({super.key});

  /// Resolves to null if the user cancelled, otherwise the send outcome.
  static Future<SendResult?> show(BuildContext context) => showDialog<SendResult>(
        context: context,
        builder: (_) => const SendToPhoneDialog(),
      );

  @override
  State<SendToPhoneDialog> createState() => _SendToPhoneDialogState();
}

class _SendToPhoneDialogState extends State<SendToPhoneDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  SendMode _mode = SendMode.text;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Re-classify as the user types, but only auto-promote text to link —
  /// demoting a deliberately chosen link would fight them mid-keystroke.
  void _onChanged() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    final looksLikeLink = _detectLink(value) != null;
    setState(() {
      _mode = looksLikeLink ? SendMode.link : SendMode.text;
    });
  }

  static String? _detectLink(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    // A bare "hello" parses fine but has no scheme — it is not a link.
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty && !_sending;

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.text = text.trim();
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _sending) return;
    setState(() => _sending = true);

    final link = _detectLink(value);
    // An explicit text mode on a link-shaped payload still opens the link —
    // that is what people expect from pasting a URL, whatever the toggle says.
    final useLink = _mode == SendMode.link || link != null;
    final ok = useLink
        ? await AdbClient.instance.openUrl(link ?? value)
        : await AdbClient.instance.sendText(value);

    if (!mounted) return;
    Navigator.of(context)
        .pop(SendResult(ok: ok, payload: value));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = _controller.text;

    return GlassModalShell(
      icon: Icon(Icons.send_rounded, size: 17, color: colors.goldPrimary),
      title: 'Send to Phone',
      subtitle: 'Text or a link, straight to the device',
      width: 480,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeSelector(
            mode: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            maxLines: 5,
            minLines: 3,
            maxLength: 4096,
            textInputAction: TextInputAction.newline,
            style: OutfitStyle.get(fontSize: 13, color: colors.textPrimary),
            decoration: _inputDecoration(context),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _mode.blurb,
                  style: OutfitStyle.get(
                      fontSize: 11, fontWeight: FontWeight.w500, color: colors.textMuted),
                ),
              ),
              Text(
                // runes, not length: an emoji is 2 UTF-16 units but one
                // character, and the budget is about what the phone accepts.
                '${value.runes.length} / 4096',
                style: FiraCodeStyle.get(
                    fontSize: 10.5, fontWeight: FontWeight.w500, color: colors.textMuted),
              ),
            ],
          ),
        ],
      ),
      actions: [
        GlassButton(
          label: 'Cancel',
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        GlassButton(
          label: _sending ? 'Sending…' : 'Send',
          icon: const Icon(Icons.arrow_upward_rounded, size: 15),
          isPrimary: _canSend,
          onPressed: _canSend ? _send : null,
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(BuildContext context) {
    final colors = context.colors;
    return InputDecoration(
      hintText: _mode == SendMode.link
          ? 'https://…'
          : 'Type a message, or paste anything…',
      hintStyle: OutfitStyle.get(
          color: colors.textSecondary.withAlpha(170), fontSize: 12.5),
      filled: true,
      fillColor: colors.inputBackground,
      alignLabelWithHint: true,
      contentPadding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      counterText: '',
      border: _border(colors.inputBorder, 1.0),
      enabledBorder: _border(colors.inputBorder, 1.0),
      focusedBorder: _border(colors.goldPrimary, 1.5),
      suffixIcon: Padding(
        padding: const EdgeInsets.only(right: 6, top: 6),
        child: IconButton(
          tooltip: 'Paste',
          icon: Icon(Icons.content_paste_rounded, size: 16, color: colors.textSecondary),
          onPressed: _pasteFromClipboard,
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Segmented Text / Link control. Reads as one control rather than two
/// buttons, so the choice is obvious before anything is typed.
class _ModeSelector extends StatelessWidget {
  final SendMode mode;
  final ValueChanged<SendMode> onChanged;

  const _ModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withAlpha(120),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.border.withAlpha(50)),
      ),
      child: Row(
        children: [
          for (final m in SendMode.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(m),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: mode == m ? colors.goldPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: mode == m
                        ? [
                            BoxShadow(
                              color: colors.goldGlow,
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        m.icon,
                        size: 14,
                        color: mode == m ? Colors.black : colors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        m.label,
                        style: OutfitStyle.get(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: mode == m ? Colors.black : colors.textSecondary,
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
}