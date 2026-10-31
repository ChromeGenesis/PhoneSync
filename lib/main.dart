import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/log/log_service.dart';
import 'services/app_services.dart';
import 'services/theme_service.dart';
import 'state/browser_controller.dart';
import 'state/connection_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts ship as bundled assets (assets/google_fonts/) — never over HTTP.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Every text arriving from the phone is copied to the PC clipboard on the
  // spot, whether or not any window is open on the inbox — that is the whole
  // point of the feature: paste on the phone, Ctrl+V on the PC.
  Services.textInbox.onReceived = (entry) {
    unawaited(Clipboard.setData(ClipboardData(text: entry.text)));
    Services.log.transfer(LogLevel.success,
        'Text received from phone (${entry.text.length} chars) — copied to clipboard');
  };

  await windowManager.ensureInitialized();
  // Deliberately NO waitUntilReadyToShow / WindowOptions here: every
  // window_manager bounds call un-maximizes the runner window, which the
  // native side already showed maximized (main.cpp). Title and initial
  // maximized state are set natively; only the min-size constraint is
  // re-applied from Dart after the first frame.
  await AppThemeService.instance.init();
  await Services.init();

  runApp(const PhoneSyncApp());

  // Kick off auto-connect after the shell has rendered so the UI shows the
  // connecting state instead of freezing on a blank frame.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final connection = ConnectionController.instance;
    connection.addListener(_onConnectionChanged);
    if (Services.config.autoConnect) {
      await connection.autoConnect();
      await BrowserController.instance.loadDeviceFolders();
      await BrowserController.instance.openLocation(BrowseLocation.recents, force: true);
      BrowserController.instance.startPolling();
    }
  });
}

void _onConnectionChanged() {
  final connection = ConnectionController.instance;
  if (!connection.isConnected) {
    BrowserController.instance.onDeviceLost();
    return;
  }
  // Every (re)connect gets a fresh transport, and adb reverse rules die with
  // their transport — so the text tunnel is re-registered here each time.
  unawaited(Services.textInbox.ensureReady().then((ok) {
    if (ok) {
      Services.log.app(LogLevel.info,
          'Text inbox live on 127.0.0.1:${Services.textInbox.port} (adb reverse)');
    } else {
      Services.log.app(LogLevel.warning,
          'Text inbox unavailable — ${Services.textInbox.tunnelError}');
    }
  }));
}
