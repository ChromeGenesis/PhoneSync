import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/theme_service.dart';
import 'ui/dialogs/settings_dialog.dart';
import 'ui/home_shell.dart';
import 'widgets/glass_snackbar.dart';

class PhoneSyncApp extends StatefulWidget {
  const PhoneSyncApp({super.key});

  @override
  State<PhoneSyncApp> createState() => _PhoneSyncAppState();
}

class _PhoneSyncAppState extends State<PhoneSyncApp> {
  /// Cmd/Ctrl+S opens Settings.
  ///
  /// The handler wraps MaterialApp rather than living inside HomeShell: the
  /// Navigator sits *above* HomeShell, so a dialog route is not its
  /// descendant and a shortcut registered down there never fires while a
  /// modal — including Settings itself — is open.
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _settingsOpen = false;

  void _openSettings() {
    // Guard against stacking a second Settings dialog on the first; the
    // shortcut is global, so a held-down key can easily re-enter here.
    if (_settingsOpen) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    _settingsOpen = true;
    showSettingsDialog(context).whenComplete(() {
      _settingsOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
              _openSettings();
              return null;
            },
          ),
        },
        child: AnimatedBuilder(
          animation: AppThemeService.instance,
          builder: (context, _) {
            final service = AppThemeService.instance;
            return MaterialApp(
              navigatorKey: _navigatorKey,
              title: 'PhoneSync',
              debugShowCheckedModeBanner: false,
              themeMode: service.themeMode,
              theme: AppThemeService.lightTheme,
              darkTheme: AppThemeService.darkTheme,
              home: const HomeShell(),
            );
          },
        ),
      ),
    );
  }
}

/// Intent for the Cmd/Ctrl+S shortcut. A distinct type so it cannot collide
/// with any other keyboard action added later.
class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

/// Shared micro-helpers for the UI layer. Intentionally tiny — anything
/// bigger belongs in a controller.

void showAppSnack(
  BuildContext context, {
  required SnackType type,
  required String title,
  required String message,
  Duration duration = const Duration(milliseconds: 2500),
  VoidCallback? onTap,
}) {
  GlassSnackbar.show(
    context,
    type: type,
    title: title,
    message: message,
    duration: duration,
    onTap: onTap,
  );
}
