import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/app_services.dart';
import 'services/theme_service.dart';
import 'state/browser_controller.dart';
import 'state/connection_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts ship as bundled assets (assets/google_fonts/) — never over HTTP.
  GoogleFonts.config.allowRuntimeFetching = false;

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
  if (!ConnectionController.instance.isConnected) {
    BrowserController.instance.onDeviceLost();
  }
}
