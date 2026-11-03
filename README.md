# PhoneSync

Wireless phone ↔ PC file sync over ADB, reimagined. A desktop companion
(Windows, macOS, Linux) that browses your Android device, moves files both
ways, and handles the everyday phone chores — pairing, screenshots, texts,
wallpapers — without touching a cable or a browser tab.

## Features

- **Wireless pairing** — Android 11+ Wi-Fi pairing flow with QR/code card,
  plus classic USB `adb tcpip` enablement
- **Auto-discovery** — subnet scan, mDNS services, and saved addresses
- **File browser** — browse phone storage with thumbnails, folder sizes,
  search, and multi-select
- **Transfers both ways** — push to phone, pull to PC, with progress and
  an activity log
- **Phone actions** — open, share, set-as-wallpaper, delete, storage info
- **Screenshots** — grab and preview device screenshots straight to PC
- **Text inbox** — read the phone's SMS inbox on the desktop
- **Glass UI** — dark/light themes, frosted panels, compact home shell

## Requirements

- [Android platform-tools](https://developer.android.com/tools/releases/platform-tools)
  (`adb` on your `PATH`, or point the app at it in Settings)
- Android device with **Wireless debugging** enabled
  (Settings → Developer options), on the same Wi-Fi as the PC

## Run it

```bash
flutter pub get
flutter run -d windows    # or -d macos / -d linux
```

Or grab a build from
[Releases](https://github.com/ChromeGenesis/PhoneSync/releases).

## How it works

Everything goes through a small `AdbClient` (`lib/core/adb/`) that wraps
the platform-tools binary — device-scoped shell commands, `push`/`pull`,
`screenshot`, `sms` queries via content providers — with all settings in
one typed store (`lib/core/config/app_config.dart`) persisted as JSON.
No root, no companion app on the phone, no cloud in the middle.

`tool/verify_*.dart` are one-shot probes (ADB presence, config dirs,
inbox parsing); run with `dart run tool/verify_adb.dart` etc.

## License

MIT — see [LICENSE](LICENSE).
