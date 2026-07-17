import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'extension_info.dart';
import 'landing_page.dart';
import 'server_routes.dart';
import 'vm_service_info.dart';

const _channel = MethodChannel('embedded_devtools');

/// Starts the Android foreground service that exempts the app process from the
/// cached-app freezer (Android 12+), so the server keeps answering while the
/// app is backgrounded. Safe no-op elsewhere.
Future<void> _startKeepAlive(int port) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await _channel.invokeMethod('startKeepAlive', {'port': port});
  } catch (_) {
    // Plugin not registered (tests, add-to-app edge cases) — the server still
    // works while the app is foregrounded.
  }
}

typedef AssetReader = Future<List<int>?> Function(String key);

/// A service worker that unregisters itself and reloads any page it controls,
/// clearing whatever a previous DevTools service worker cached.
const _killServiceWorkerJs = '''
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await self.registration.unregister();
    const clients = await self.clients.matchAll();
    for (const client of clients) {
      if ('navigate' in client) client.navigate(client.url);
    }
  })());
});
''';

Future<List<int>?> _bundleAssetReader(String key) async {
  try {
    final data = await rootBundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

/// Reads the extension manifest written by `dart run embedded_devtools:bundle`.
Future<List<DevToolsExtensionInfo>> _readExtensionManifest(
    AssetReader read) async {
  final bytes = await read(extensionManifestAssetKey);
  if (bytes == null) return const [];
  try {
    final list = jsonDecode(utf8.decode(bytes)) as List<Object?>;
    return [
      for (final e in list)
        DevToolsExtensionInfo.fromJson(e! as Map<String, Object?>),
    ];
  } catch (_) {
    return const [];
  }
}

/// Serves the full Flutter DevTools suite from inside this app.
///
/// Inert in release builds: the AOT product engine has no VM service, so there
/// is nothing for DevTools to connect to.
class EmbeddedDevTools {
  EmbeddedDevTools._();

  /// Notifies when the server comes up or goes down, so UI (the overlay
  /// bubble) can react to the async [start].
  static final ValueNotifier<DevToolsServer?> serverNotifier =
      ValueNotifier(null);

  static DevToolsServer? get _server => serverNotifier.value;
  static set _server(DevToolsServer? value) => serverNotifier.value = value;

  /// The running server, if [start] has been called and succeeded.
  static DevToolsServer? get server => _server;

  /// Starts the server (idempotent). Returns null in release mode, or if no
  /// port in `[port, port + 10)` could be bound.
  ///
  /// [keepAlive] (Android) runs a foreground service with a persistent
  /// notification so the server survives the app being backgrounded — needed
  /// when browsing DevTools from the phone's own browser.
  ///
  /// [extensions] defaults to whatever the `bundle` CLI discovered and
  /// recorded in the asset manifest; pass a list to override.
  ///
  /// [isRelease], [vmInfo] and [assetReader] exist for tests.
  static Future<DevToolsServer?> start({
    int port = 9200,
    bool keepAlive = true,
    List<DevToolsExtensionInfo>? extensions,
    bool logRequests = false,
    bool? isRelease,
    VmServiceInfo? vmInfo,
    AssetReader? assetReader,
  }) async {
    if (isRelease ?? kReleaseMode) return null;
    if (_server != null) return _server;
    final read = assetReader ?? _bundleAssetReader;
    final vm = vmInfo ?? await VmServiceInfo.discover();
    HttpServer? http;
    for (var p = port; p < port + 10; p++) {
      try {
        http = await HttpServer.bind(InternetAddress.anyIPv4, p);
        break;
      } on SocketException {
        if (p == 0) rethrow;
      }
    }
    if (http == null) return null;
    final exts = extensions ?? await _readExtensionManifest(read);
    _server = DevToolsServer._(http, vm, read, exts, logRequests);
    if (keepAlive) await _startKeepAlive(http.port);
    return _server;
  }
}

/// Handle to the running server; exposes the URLs DevTools can be opened at.
abstract class DevToolsServerHandle {
  int get port;

  /// The `/qa` landing page on this device.
  Uri get localUrl;

  /// Full DevTools URL (dart2js renderer, connected through this server's ws
  /// proxy) for an in-app WebView or the device browser. Null when no VM
  /// service is available (release builds).
  Uri? get devToolsUrl;

  /// Extensions bundled into this app and advertised to DevTools.
  List<DevToolsExtensionInfo> get extensions;

  /// One landing-page URL per non-loopback network interface, for opening
  /// DevTools from a PC on the same network.
  Future<List<Uri>> lanUrls();
}

class DevToolsServer implements DevToolsServerHandle {
  DevToolsServer._(this._http, this._vm, this._readAsset, this._extensions,
      this._logRequests) {
    _http.listen(_handle);
  }

  final HttpServer _http;
  final VmServiceInfo? _vm;
  final AssetReader _readAsset;
  final List<DevToolsExtensionInfo> _extensions;
  final bool _logRequests;

  @override
  int get port => _http.port;

  @override
  List<DevToolsExtensionInfo> get extensions => List.unmodifiable(_extensions);

  @override
  Uri get localUrl => Uri.parse('http://127.0.0.1:$port/qa');

  @override
  Uri? get devToolsUrl {
    final vm = _vm;
    if (vm == null) return null;
    // The proxy websocket lives on THIS server (same host+port), at the VM's
    // ws path. compiler=js forces the dart2js+canvaskit build — the wasm build
    // needs cross-origin isolation we can't grant over plain http.
    final ws = 'ws://127.0.0.1:$port${vm.wsPath}';
    return Uri.parse('http://127.0.0.1:$port/?ide=EmbeddedDevTools'
        '&uri=${Uri.encodeComponent(ws)}&compiler=js');
  }

  @override
  Future<List<Uri>> lanUrls() async {
    final urls = <Uri>[];
    for (final iface
        in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          urls.add(Uri.parse('http://${addr.address}:$port/qa'));
        }
      }
    }
    return urls;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final vmWsPath = _vm?.wsPath ?? '/__no_vm__';
      final route = routeRequest(req.uri.path, vmWsPath: vmWsPath);
      if (_logRequests && route.kind != ServerRouteKind.devtoolsAsset) {
        // ignore: avoid_print
        print('[embedded_devtools] ${route.kind.name} <- ${req.uri}');
      }
      switch (route.kind) {
        case ServerRouteKind.vmWebSocket:
          await _proxyWebSocket(req);
        case ServerRouteKind.wasmOptOut:
          // Only opt out for the wasm-renderer key; other prefs get a benign
          // null so DevTools falls back to its defaults.
          final optOut =
              req.uri.queryParameters['key'] == 'experiment.wasmOptOut';
          req.response.headers.contentType = ContentType.json;
          req.response.write(optOut ? 'true' : 'null');
          await req.response.close();
        case ServerRouteKind.killServiceWorker:
          req.response.headers
              .set(HttpHeaders.contentTypeHeader, 'text/javascript');
          req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
          req.response.write(_killServiceWorkerJs);
          await req.response.close();
        case ServerRouteKind.landing:
          req.response.headers.contentType = ContentType.html;
          req.response.write(_vm == null
              ? landingPageNoVmHtml()
              : landingPageHtml(vmPort: _vm.port, vmWsPath: _vm.wsPath));
          await req.response.close();
        case ServerRouteKind.apiPing:
          req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
          req.response.write('OK');
          await req.response.close();
        case ServerRouteKind.serveExtensions:
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'extensions': [for (final e in _extensions) e.toDevToolsJson()],
            'logs': <String>[],
          }));
          await req.response.close();
        case ServerRouteKind.extensionEnabledState:
          // Report every bundled extension as enabled, so DevTools shows it
          // without an enable/disable prompt (set requests are a no-op).
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode('enabled'));
          await req.response.close();
        case ServerRouteKind.apiOther:
          req.response.headers.contentType = ContentType.json;
          req.response.write('null');
          await req.response.close();
        case ServerRouteKind.extensionAsset:
          await _serveExtensionAsset(req, route.assetKey);
        case ServerRouteKind.devtoolsAsset:
          final bytes = await _readAsset(route.assetKey);
          if (bytes == null) {
            req.response.statusCode = HttpStatus.notFound;
            req.response.headers.contentType = ContentType.text;
            req.response.write(
                'Asset ${route.assetKey} is not bundled in this app.\n'
                'Run `dart run embedded_devtools:bundle` in the app directory.');
          } else {
            req.response.headers
                .set(HttpHeaders.contentTypeHeader, mimeFor(route.assetKey));
            req.response.add(bytes);
          }
          await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Serves a file for an extension iframe. [idAndRel] is `<id>/<rel>`.
  ///
  /// - `index.html` gets its `<base href="/">` rewritten to the extension's
  ///   sub-path, so its relative assets resolve here and not at the root
  ///   (where DevTools' own bootstrap lives).
  /// - `canvaskit/*` is served from the shared DevTools build — same engine
  ///   revision, so every extension reuses one copy instead of shipping 37 MB.
  /// - everything else comes from the extension's own asset root.
  Future<void> _serveExtensionAsset(HttpRequest req, String idAndRel) async {
    final slash = idAndRel.indexOf('/');
    final id = slash < 0 ? idAndRel : idAndRel.substring(0, slash);
    var rel = slash < 0 ? '' : idAndRel.substring(slash + 1);
    if (rel.isEmpty) rel = 'index.html';

    DevToolsExtensionInfo? ext;
    for (final e in _extensions) {
      if (e.identifier == id) ext = e;
    }
    if (ext == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }

    if (rel == 'index.html') {
      final bytes = await _readAsset('${ext.assetRoot}/index.html');
      if (bytes == null) {
        req.response.statusCode = HttpStatus.notFound;
        req.response.headers.contentType = ContentType.text;
        req.response.write("Extension '${ext.name}' is not bundled. Re-run "
            '`dart run embedded_devtools:bundle`.');
        await req.response.close();
        return;
      }
      final html = utf8.decode(bytes).replaceFirst(
          '<base href="/">', '<base href="$extensionUrlPrefix$id/">');
      req.response.headers.contentType = ContentType.html;
      req.response.write(html);
      await req.response.close();
      return;
    }

    final assetKey = rel.startsWith('canvaskit/')
        ? 'assets/devtools/$rel'
        : '${ext.assetRoot}/$rel';
    final bytes = await _readAsset(assetKey);
    if (bytes == null) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    req.response.headers.set(HttpHeaders.contentTypeHeader, mimeFor(rel));
    req.response.add(bytes);
    await req.response.close();
  }

  Future<void> _proxyWebSocket(HttpRequest req) async {
    final vm = _vm;
    if (vm == null || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final WebSocket upstream;
    try {
      upstream =
          await WebSocket.connect('ws://127.0.0.1:${vm.port}${vm.wsPath}');
    } catch (_) {
      req.response.statusCode = HttpStatus.badGateway;
      await req.response.close();
      return;
    }
    final client = await WebSocketTransformer.upgrade(req);
    client.listen(upstream.add,
        onDone: () => upstream.close(), onError: (_) => upstream.close());
    upstream.listen(client.add,
        onDone: () => client.close(), onError: (_) => client.close());
  }

  Future<void> stop() async {
    await _http.close(force: true);
    if (EmbeddedDevTools._server == this) EmbeddedDevTools._server = null;
  }
}
