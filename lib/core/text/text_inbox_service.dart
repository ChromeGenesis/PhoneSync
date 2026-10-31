import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_client.dart';

/// One piece of text sent from the phone.
class TextInboxEntry {
  final String id;
  final String text;
  final DateTime received;

  TextInboxEntry({required this.id, required this.text, required this.received});
}

/// Phone → PC text, with no companion app on the phone.
///
/// The desktop app owns an HTTP server bound to loopback and registers an
/// `adb reverse` rule so `127.0.0.1:<port>` on the *phone* is that server.
/// The "app" on the phone is a browser tab: paste, send, and the text arrives
/// here. Loopback-only means nothing on the LAN can reach it — the only client
/// is whatever tunnels in through the adb transport.
class TextInboxService {
  TextInboxService._();
  static final TextInboxService instance = TextInboxService._();

  static const _maxEntries = 100;
  static const _maxBodyBytes = 1 << 20;

  final List<TextInboxEntry> _entries = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  HttpServer? _server;
  String? _tunnelError;
  int _unread = 0;
  int _seq = 0;

  /// Fired for every arrival, on the service side — this is where the copy to
  /// the PC clipboard happens, so it works whether or not any UI is open.
  void Function(TextInboxEntry entry)? onReceived;

  List<TextInboxEntry> get entries => List.unmodifiable(_entries);
  int get unreadCount => _unread;
  bool get isServing => _server != null;
  int? get port => _server?.port;

  /// Why the adb reverse tunnel could not be registered, when it failed.
  String? get tunnelError => _tunnelError;

  /// Broadcast of every state change — new entry, unread reset, server or
  /// tunnel status. Pure Dart on purpose: the UI consumes it with a plain
  /// StreamBuilder, and this file stays runnable under a bare `dart run`
  /// smoke test with no Flutter SDK on the machine.
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void markAllRead() {
    if (_unread == 0) return;
    _unread = 0;
    _notify();
  }

  void clear() {
    _entries.clear();
    _unread = 0;
    _notify();
  }

  /// Starts the loopback server (once) and registers the reverse tunnel.
  /// Safe to call on every (re)connect: a reconnect gets a new transport, and
  /// reverse rules die with their transport, so the rule has to be
  /// re-registered every time. The tunnel targets the device adb currently has
  /// pinned — AdbClient injects `-s` itself.
  Future<bool> ensureReady() async {
    final serving = await _ensureServer();
    if (!serving) return false;
    return _registerTunnel();
  }

  /// Binds 127.0.0.1 on an ephemeral port — no collision risk, and the OS
  /// gives back a port nothing else is watching.
  Future<bool> _ensureServer() async {
    if (_server != null) return true;
    try {
      final server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(_handle, onError: (_) {});
      _server = server;
      return true;
    } catch (e) {
      _tunnelError = 'could not start local server: $e';
      return false;
    }
  }

  Future<bool> _registerTunnel() async {
    final p = _server!.port;
    final res = await AdbClient.instance.run(['reverse', 'tcp:$p', 'tcp:$p']);
    if (!res.ok) {
      _tunnelError = (res.stderr.trim().isNotEmpty
              ? res.stderr.trim()
              : res.stdout.trim())
          .split('\n')
          .last;
      return false;
    }
    _tunnelError = null;
    return true;
  }

  /// Opens the paste page in the phone's browser via the existing intent
  /// bridge. The tunnel must be registered first — see [ensureReady].
  Future<bool> openOnPhone() async {
    final p = _server?.port;
    if (p == null) return false;
    return AdbClient.instance.openUrl('http://127.0.0.1:$p');
  }

  Future<void> stop() async {
    final p = port;
    _server?.close(force: true);
    _server = null;
    if (p != null) {
      // Remove the rule while the server record still knows the port.
      await AdbClient.instance.run(['reverse', '--remove', 'tcp:$p']);
    }
  }

  // ------------------------------------------------------------- HTTP layer

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
        await _reply(req, 200, utf8.encode(_pageHtml), 'text/html; charset=utf-8');
      } else if (req.method == 'POST' && path == '/send') {
        final body = await _readBody(req);
        if (body == null) {
          await _reply(req, 413, utf8.encode('too large'), 'text/plain');
          return;
        }
        final text = body.trim();
        if (text.isNotEmpty) {
          final entry = TextInboxEntry(
            id: 'e${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
            text: text,
            received: DateTime.now(),
          );
          _entries.insert(0, entry);
          if (_entries.length > _maxEntries) _entries.removeLast();
          _unread++;
          onReceived?.call(entry);
          _notify();
        }
        await _reply(req, 200, utf8.encode('SENT'), 'text/plain');
      } else if (req.method == 'GET' && path == '/favicon.ico') {
        req.response.statusCode = 204;
        await req.response.close();
      } else {
        await _reply(req, 404, utf8.encode('not found'), 'text/plain');
      }
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Reads the request body as UTF-8, or null when it exceeds the cap.
  ///
  /// Always consumes the stream to the end, even on overflow: returning early
  /// would cancel the subscription, and a half-read request that gets a
  /// response resets the connection under the client instead of delivering
  /// the status code.
  Future<String?> _readBody(HttpRequest req) async {
    final builder = BytesBuilder(copy: false);
    var overflow = false;
    var total = 0;
    await for (final chunk in req) {
      total += chunk.length;
      if (total > _maxBodyBytes) {
        overflow = true;
        continue;
      }
      builder.add(chunk);
    }
    if (overflow) return null;
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  Future<void> _reply(HttpRequest req, int status, List<int> body, String contentType) async {
    req.response.statusCode = status;
    req.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    req.response.add(body);
    await req.response.close();
  }

  // ---------------------------------------------------------------- the page

  /// The paste page. 127.0.0.1 is a trustworthy origin, so the clipboard
  /// read API works from plain HTTP — the Paste button can pull the phone's
  /// clipboard straight into the box with one tap.
  static const _pageHtml = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0b1020">
<title>PhoneSync — Text to PC</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{min-height:100vh;display:flex;align-items:center;justify-content:center;
       background:radial-gradient(1200px 700px at 20% -10%,#1c2a4a 0%,#0b1020 55%,#080b16 100%);
       font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;color:#e8ecf4;padding:20px}
  .card{width:100%;max-width:460px;background:rgba(255,255,255,.045);
        border:1px solid rgba(255,255,255,.09);border-radius:22px;padding:26px 22px;
        box-shadow:0 24px 60px rgba(0,0,0,.45)}
  .brand{font-size:11px;font-weight:800;letter-spacing:.35em;color:#f0c75e;margin-bottom:4px}
  h1{font-size:19px;font-weight:700;margin-bottom:6px}
  p.sub{font-size:12.5px;color:#98a2b8;line-height:1.5;margin-bottom:18px}
  textarea{width:100%;height:34vh;min-height:150px;resize:vertical;background:rgba(255,255,255,.05);
           color:#e8ecf4;border:1px solid rgba(255,255,255,.12);border-radius:14px;padding:14px;
           font-size:15px;line-height:1.5;outline:none}
  textarea:focus{border-color:#f0c75e;box-shadow:0 0 0 3px rgba(240,199,94,.14)}
  .row{display:flex;gap:10px;margin-top:14px}
  button{flex:1;border:0;border-radius:13px;padding:15px;font-size:15.5px;font-weight:700;
         cursor:pointer;transition:transform .06s ease,filter .15s ease}
  button:active{transform:scale(.97)}
  .paste{background:rgba(255,255,255,.07);color:#c9d2e3;border:1px solid rgba(255,255,255,.12)!important}
  .send{background:#f0c75e;color:#161206;box-shadow:0 6px 20px rgba(240,199,94,.25)}
  button:disabled{opacity:.45;cursor:default}
  #msg{margin-top:13px;min-height:20px;font-size:13px;color:#7ee787;text-align:center}
  #msg.err{color:#ff8f8f}
</style></head><body>
<div class="card">
  <div class="brand">PHONESYNC</div>
  <h1>Send text to your PC</h1>
  <p class="sub">Paste or type below, then send. It lands on your computer instantly — already copied to its clipboard.</p>
  <textarea id="t" placeholder="Paste anything here…" autofocus></textarea>
  <div class="row">
    <button class="paste" onclick="paste()">Paste</button>
    <button class="send" id="send" onclick="send()">Send to PC</button>
  </div>
  <div id="msg"></div>
</div>
<script>
var btn=document.getElementById('send'),msg=document.getElementById('msg'),t=document.getElementById('t');
function say(s,err){msg.textContent=s;msg.className=err?'err':'';}
async function paste(){
  try{
    const v=await navigator.clipboard.readText();
    if(!v){say('Clipboard is empty',true);return;}
    t.value=(t.value?t.value+'\n':'')+v;
    t.focus();
  }catch(e){say('Clipboard read blocked — paste manually',true);}
}
async function send(){
  const v=t.value.trim();
  if(!v){say('Nothing to send',true);return;}
  btn.disabled=true;
  try{
    const r=await fetch('/send',{method:'POST',body:t.value});
    if(r.ok){say('Sent — check your PC');t.value='';}
    else say('Failed ('+r.status+')',true);
  }catch(e){say("Couldn't reach the PC — is it still connected?",true);}
  btn.disabled=false;
}
</script></body></html>''';
}
