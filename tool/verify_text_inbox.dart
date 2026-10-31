// End-to-end smoke test for the text inbox: real HTTP server, real requests,
// optional real device tunnel.
//
//   dart run tool/verify_text_inbox.dart
//
// Pass --tunnel to also register the adb reverse rule and round-trip a POST
// through the phone itself (requires a connected device):
//
//   dart run tool/verify_text_inbox.dart --tunnel

// These scripts import lib/ relatively rather than via `package:phonesync/` on
// purpose: they are meant to be runnable with a bare Dart SDK, including on a
// machine with no Flutter installed and therefore no package config. A
// `package:` import would need `flutter pub get` to have been run first.
// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import '../lib/core/text/text_inbox_service.dart';

var _failures = 0;

void check(bool ok, String what) {
  stdout.writeln('${ok ? "PASS" : "FAIL"}: $what');
  if (!ok) _failures++;
}

Future<void> main(List<String> args) async {
  final inbox = TextInboxService.instance;
  TextInboxEntry? received;
  inbox.onReceived = (e) => received = e;

  // 1. Server binds and serves the page.
  await inbox.ensureReady();
  check(inbox.isServing, 'loopback server is up on port ${inbox.port}');

  final client = HttpClient();
  final port = inbox.port!;

  // 2. GET / serves the paste page.
  final page = await _request(client, 'GET', port, '/');
  check(page?.statusCode == 200, 'GET / -> ${page?.statusCode}');
  check(
      page != null && page.body.contains('Send to PC') && page.body.contains('<textarea'),
      'page contains the paste UI');

  // 3. POST /send stores the text and fires onReceived.
  final post = await _request(client, 'POST', port, '/send',
      body: 'smoke test — hello from the tool 😊');
  check(post?.statusCode == 200, 'POST /send -> ${post?.statusCode}');
  check(
      inbox.entries.isNotEmpty && inbox.entries.first.text.contains('smoke test'),
      'entry stored: "${inbox.entries.firstOrNull?.text}"');
  check(received != null && received == inbox.entries.firstOrNull,
      'onReceived fired for the arrival');
  check(inbox.unreadCount == 1, 'unread count is 1');

  // 4. Unicode round-trips intact (emoji are the classic corruption case).
  check(inbox.entries.isNotEmpty && inbox.entries.first.text.contains('😊'),
      'emoji survived the round trip');

  // 5. Oversized bodies are refused, not crash.
  final big = await _request(client, 'POST', port, '/send', body: 'x' * (1 << 21));
  check(big?.statusCode == 413, 'oversized POST -> ${big?.statusCode}');

  // 6. Optional real tunnel test through the phone.
  if (args.contains('--tunnel')) {
    stdout.writeln('\n-- with tunnel --');
    final devices = await _deviceSerial();
    if (devices == null) {
      stdout.writeln('SKIP: no device connected');
    } else {
      final ok = await inbox.ensureReady();
      check(ok, 'adb reverse registered for $devices');
      if (ok) {
        final viaPhone = await _request(client, 'POST', port, '/send',
            body: 'tunnel test',
            viaDevice: true);
        check(viaPhone?.statusCode == 200,
            'POST from the phone through the tunnel -> ${viaPhone?.statusCode}');
        check(inbox.entries.firstOrNull?.text == 'tunnel test',
            'text arrived from the phone: "${inbox.entries.firstOrNull?.text}"');
      }
    }
  }

  await inbox.stop();
  client.close();
  check(!inbox.isServing, 'server stopped cleanly');

  stdout.writeln(_failures == 0 ? '\nALL CHECKS PASSED' : '\n$_failures CHECK(S) FAILED');
  exitCode = _failures == 0 ? 0 : 1;
}

Future<String?> _deviceSerial() async {
  final res = await Process.run('adb', ['devices']);
  for (final line in res.stdout.toString().split('\n').skip(1)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1] == 'device') return parts[0];
  }
  return null;
}

class _Response {
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
}

Future<_Response?> _request(HttpClient client, String method, int port, String path,
    {String? body, bool viaDevice = false}) async {
  try {
    if (viaDevice) {
      // Route the request through the phone: shell curl hits 127.0.0.1 on
      // the device, which the reverse rule maps back to this server.
      final res = await Process.run('adb', [
        'shell',
        'curl -s -o /dev/null -w "%{http_code}" -X POST -d "$body" '
            'http://127.0.0.1:$port/send'
      ]);
      final code = int.tryParse(res.stdout.toString().trim()) ?? 0;
      return _Response(code, res.stdout.toString());
    }
    final open =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (body != null) {
      // write() validates against the request's charset — without an explicit
      // UTF-8 content type, emoji in the body throw before they are sent.
      open.headers.set(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8');
      open.write(body);
    }
    final res = await open.close();
    return _Response(res.statusCode, await res.transform(utf8.decoder).join());
  } catch (e) {
    stderr.writeln('request failed: $e');
    return null;
  }
}
