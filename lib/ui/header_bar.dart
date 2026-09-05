import 'package:flutter/material.dart';

import '../app.dart';
import '../core/adb/adb_models.dart';
import '../services/app_services.dart';
import '../services/theme_service.dart';
import '../state/browser_controller.dart';
import '../state/connection_controller.dart';
import '../widgets/glass/glass_button.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/shared/live_badge.dart';
import '../widgets/shared/text_style_cache.dart';
import '../widgets/shared/theme_mode_selector.dart';
import 'dialogs/settings_dialog.dart';
import 'home_shell.dart';

/// Broadcast-bar-style header: app identity, device status, prominent theme
/// switch, refresh, and settings on the right.
class HeaderBar extends StatelessWidget {
  final ShellTab activeTab;
  final ValueChanged<ShellTab> onTabSelected;

  const HeaderBar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: Listenable.merge([
        ConnectionController.instance,
        BrowserController.instance,
        Services.transfers,
      ]),
      builder: (context, _) {
        final connection = ConnectionController.instance;
        return Container(
          height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.surface.withAlpha(90), colors.surface.withAlpha(40)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(bottom: BorderSide(color: colors.border.withAlpha(40))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _logoTile(context),
              const SizedBox(width: 11),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PHONESYNC',
                    style: OutfitStyle.get(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                        letterSpacing: 1.4),
                  ),
                  Text(
                    'v1.0 · wireless adb sync',
                    style: OutfitStyle.get(
                        fontSize: 9, fontWeight: FontWeight.w500, color: colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              _StatusChip(connection: connection),
              const Spacer(),
              const ThemeModeSelector(compact: true),
              const SizedBox(width: 10),
              if (Services.transfers.isBusy) ...[
                const SizedBox(width: 2),
                _TransferChip(onOpen: () => onTabSelected(ShellTab.transfers)),
                const SizedBox(width: 10),
              ],
              GlassButton(
                label: 'Refresh',
                icon: const Icon(Icons.refresh_rounded, size: 15),
                onPressed: connection.isConnected
                    ? () async {
                        await BrowserController.instance.refresh(logChange: true);
                        await BrowserController.instance.loadDeviceFolders();
                      }
                    : null,
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                isActive: false,
                onPressed: () => showSettingsDialog(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _logoTile(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: colors.goldGlow, blurRadius: 14, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: const Image(
          image: AssetImage('assets/app_icon.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ConnectionController connection;
  const _StatusChip({required this.connection});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = connection.status;
    final connected = status == ConnectionStatus.connected;
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (colors.emeraldLive, connection.deviceLabel),
      ConnectionStatus.connecting => (colors.goldPrimary, 'Connecting…'),
      ConnectionStatus.disconnected => (colors.roseDanger, 'No device'),
    };

    return GestureDetector(
      onTap: status == ConnectionStatus.disconnected ? () => _reconnect(context) : null,
      // No outer container — a boxed chip this tall crowds the header's
      // bottom edge. Just the icon tile, identity, and live badge.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withAlpha(26),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: color.withAlpha(70)),
              ),
              child: Icon(
                connected
                    ? Icons.smartphone_rounded
                    : status == ConnectionStatus.connecting
                        ? Icons.phonelink_ring_rounded
                        : Icons.phonelink_off_rounded,
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: OutfitStyle.get(
                      fontSize: 12, fontWeight: FontWeight.w700, color: colors.textPrimary),
                ),
                if (connected)
                  Text(
                    connection.addressLabel,
                    style: FiraCodeStyle.get(
                        fontSize: 9.5, fontWeight: FontWeight.w500, color: colors.textMuted),
                  ),
              ],
            ),
            const SizedBox(width: 9),
            LiveBadge(
              label: switch (status) {
                ConnectionStatus.connected => 'LIVE',
                ConnectionStatus.connecting => 'SCAN',
                ConnectionStatus.disconnected => 'OFFLINE',
              },
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reconnect(BuildContext context) async {
    final c = ConnectionController.instance;
    await c.rescan();
    if (c.isConnected) {
      await BrowserController.instance.loadDeviceFolders();
      await BrowserController.instance.openLocation(BrowseLocation.recents, force: true);
      BrowserController.instance.startPolling();
    } else if (context.mounted) {
      showAppSnack(
        context,
        type: SnackType.error,
        title: 'No device found',
        message: 'Check Wi-Fi ADB is enabled, or plug in via USB and rescan.',
      );
    }
  }
}

class _TransferChip extends StatelessWidget {
  final VoidCallback onOpen;
  const _TransferChip({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final service = Services.transfers;
    final active = service.active;
    final totalItems = active.fold<int>(0, (s, j) => s + j.items.length);
    final doneItems = active.fold<int>(0, (s, j) => s + j.doneItems);
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: colors.goldPrimary.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.goldPrimary.withAlpha(90)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.goldPrimary),
            ),
            const SizedBox(width: 8),
            Text(
              '$doneItems / $totalItems',
              style: OutfitStyle.get(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: colors.textGold),
            ),
          ],
        ),
      ),
    );
  }
}
