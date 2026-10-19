// Verifies AdbClient resolves adb without relying on PATH.
//
// Run with a scrubbed environment to mimic a Finder/Dock launch, where
// launchd hands the app no PATH at all:
//
//   env -i HOME="$HOME" dart run tool/verify_adb.dart
//
// Compare against the same script in a normal shell — both should succeed.

import 'dart:io';

import '../lib/core/adb/adb_client.dart';

Future<void> main() async {
  final adb = AdbClient.instance;
  final path = Platform.environment['PATH'];

  stdout.writeln('PATH env var: ${path == null ? '(unset)' : path}');
  stdout.writeln('configured:    ${adb.adbConfigured}');
  stdout.writeln('available:     ${adb.adbAvailable}');
  stdout.writeln('resolved:      ${adb.adbResolved ?? '-'}');
  stdout.writeln('failure:       ${adb.adbResolveFailure ?? '-'}');

  if (!adb.adbAvailable) {
    stderr.writeln('\nFAIL: adb could not be resolved.');
    exitCode = 1;
    return;
  }

  // Same code path the app's auto-connect takes.
  final res = await adb.run(['devices', '-l']);
  if (!res.ok) {
    stderr.writeln('\nFAIL: `adb devices -l` failed '
        '(exit ${res.exitCode}, failure ${res.failure.name}): ${res.stderr.trim()}');
    exitCode = 1;
    return;
  }

  final devices = await adb.listDevices();
  stdout.writeln('\ndevices: ${devices.length}');
  for (final d in devices) {
    stdout.writeln('  ${d.id}  ${d.model}  ${d.isWireless ? 'wireless' : 'usb'}');
  }

  if (devices.isEmpty) {
    stderr.writeln('\nFAIL: adb ran but reported no devices.');
    exitCode = 1;
    return;
  }

  final model = await adb.deviceModel(devices.first.id);
  stdout.writeln('\nOK: reached ${model ?? devices.first.id} with no PATH help.');

  await _verifyMissingIsSurfaced(adb);
}

/// The bug this whole exercise exists for: a missing adb used to come back as
/// an empty device list, indistinguishable from "no phone attached".
Future<void> _verifyMissingIsSurfaced(AdbClient adb) async {
  stdout.writeln('\n--- negative checks ---');
  var failures = 0;

  for (final bogus in ['/nonexistent/dir/adb', 'definitely_not_adb_xyz']) {
    adb.adbExecutable = bogus;
    final available = adb.adbAvailable;
    final reason = adb.adbResolveFailure;

    final res = await adb.run(['devices', '-l']);
    final devices = await adb.listDevices();

    final checks = <String, bool>{
      'adbAvailable == false': !available,
      'adbResolveFailure set': reason != null && reason.isNotEmpty,
      'run() flags adbMissing': res.adbMissing,
      'run() is not ok': !res.ok,
      'listDevices empty': devices.isEmpty,
    };

    stdout.writeln('\n$bogus');
    stdout.writeln('  reason: ${reason ?? '-'}');
    checks.forEach((label, pass) {
      stdout.writeln('  ${pass ? 'PASS' : 'FAIL'}  $label');
      if (!pass) failures++;
    });
  }

  // Restore, and confirm the resolver recovers rather than sticking on failure.
  adb.adbExecutable = 'adb';
  final recovered = await adb.listDevices();
  stdout.writeln('\nrestore: available=${adb.adbAvailable} '
      'resolved=${adb.adbResolved} devices=${recovered.length}');
  if (!adb.adbAvailable || recovered.isEmpty) {
    stdout.writeln('  FAIL  resolver did not recover after a valid path');
    failures++;
  }

  stdout.writeln(failures == 0
      ? '\nOK: missing adb is reported as missing, not as "no devices".'
      : '\nFAIL: $failures check(s) failed.');
  if (failures > 0) exitCode = 1;
}