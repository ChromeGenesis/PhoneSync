// Smoke-check for AppDirs. Pure Dart, so it runs without the Flutter SDK:
//
//   dart run tool/verify_app_dirs.dart
//
// Run it with a scrubbed environment to confirm the fallbacks hold when the
// usual variables are missing (as they are for a GUI-launched macOS app):
//
//   env -i HOME="$HOME" dart run tool/verify_app_dirs.dart

// Relative import for the same reason as verify_adb.dart: runnable with a bare
// Dart SDK, no Flutter or package config required.
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import '../lib/core/config/app_dirs.dart';

void main() {
  final env = Platform.environment;
  stdout.writeln('platform:   ${Platform.operatingSystem}');
  stdout.writeln('HOME:        ${env['HOME'] ?? '(unset)'}');
  stdout.writeln('APPDATA:     ${env['APPDATA'] ?? '(unset)'}');
  stdout.writeln('XDG_*_HOME:  ${env['XDG_CONFIG_HOME'] ?? '(unset)'}'
      ' / ${env['XDG_CACHE_HOME'] ?? '(unset)'}');
  stdout.writeln('');

  // Must be absolute, platform-native, and must never be the filesystem root.
  final checks = <String, bool>{
    'config is absolute': AppDirs.configDir.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(AppDirs.configDir),
    'cache is absolute': AppDirs.cacheDir.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(AppDirs.cacheDir),
    'save dir is absolute': AppDirs.defaultSaveDir.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(AppDirs.defaultSaveDir),
    'config names the app': AppDirs.configDir.contains('PhoneSync'),
    'cache names the app': AppDirs.cacheDir.contains('PhoneSync'),
    'cache is not systemTemp':
        !AppDirs.cacheDir.startsWith(Directory.systemTemp.path),
  };

  stdout.writeln('config:  ${AppDirs.configDir}');
  stdout.writeln('cache:   ${AppDirs.cacheDir}');
  stdout.writeln('saveDir: ${AppDirs.defaultSaveDir}');
  stdout.writeln('');

  var failures = 0;
  checks.forEach((label, pass) {
    stdout.writeln('${pass ? 'PASS' : 'FAIL'}  $label');
    if (!pass) failures++;
  });

  stdout.writeln(failures == 0
      ? '\nOK: app directories resolve correctly on this platform.'
      : '\nFAIL: $failures check(s) failed.');
  if (failures > 0) exitCode = 1;
}