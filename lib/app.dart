import 'package:flutter/material.dart';

import 'services/theme_service.dart';
import 'ui/home_shell.dart';
import 'widgets/glass_snackbar.dart';

class PhoneSyncApp extends StatelessWidget {
  const PhoneSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeService.instance,
      builder: (context, _) {
        final service = AppThemeService.instance;
        return MaterialApp(
          title: 'PhoneSync',
          debugShowCheckedModeBanner: false,
          themeMode: service.themeMode,
          theme: AppThemeService.lightTheme,
          darkTheme: AppThemeService.darkTheme,
          home: const HomeShell(),
        );
      },
    );
  }
}

/// Shared micro-helpers for the UI layer. Intentionally tiny — anything
/// bigger belongs in a controller.

void showAppSnack(
  BuildContext context, {
  required SnackType type,
  required String title,
  required String message,
}) {
  GlassSnackbar.show(context, type: type, title: title, message: message);
}
