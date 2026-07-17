/// Pure request-classification logic for the embedded DevTools server.
enum ServerRouteKind {
  /// The `/qa` landing page listing the URLs DevTools can be opened at.
  landing,

  /// The app's own VM-service websocket, proxied through this server.
  vmWebSocket,

  /// A file from the bundled DevTools web build.
  devtoolsAsset,

  /// DevTools asks its server whether the user opted out of the wasm renderer.
  wasmOptOut,

  /// A self-unregistering service worker (see [killServiceWorkerJs]).
  killServiceWorker,

  /// DevTools probes this to decide a server is present; a 200 here unlocks
  /// server-backed features, including extension discovery.
  apiPing,

  /// `serveAvailableExtensions` — the list of DevTools extensions to show.
  serveExtensions,

  /// `extensionEnabledState` — read/set whether an extension is enabled.
  extensionEnabledState,

  /// Any other `/api/...` call; answered benignly so DevTools' init doesn't
  /// error now that it believes a server is present.
  apiOther,

  /// A file for an extension's iframe, served at
  /// `/devtools_extensions/<id>/<rel>`. [ServerRoute.assetKey] is `<id>/<rel>`.
  extensionAsset,
}

class ServerRoute {
  const ServerRoute(this.kind, [this.assetKey = '']);

  final ServerRouteKind kind;
  final String assetKey;
}

/// Path prefix DevTools uses for extension iframes.
const extensionUrlPrefix = '/devtools_extensions/';

/// Classifies a request path.
///
/// The DevTools web build is served at the server root (its `index.html`
/// declares `<base href="/">`), the landing page lives at `/qa`, and the
/// VM-service websocket path (auth code + `/ws`) is proxied.
ServerRoute routeRequest(String path,
    {required String vmWsPath, String assetPrefix = 'assets/devtools'}) {
  if (path == vmWsPath) return const ServerRoute(ServerRouteKind.vmWebSocket);
  if (path == '/qa') return const ServerRoute(ServerRouteKind.landing);
  // DevTools' bootstrap asks whether the user opted out of the wasm (skwasm)
  // renderer. skwasm needs SharedArrayBuffer (cross-origin isolation), which
  // this plain-http server can't grant — so it renders blank. Always opt out,
  // forcing the dart2js+canvaskit build that works everywhere.
  if (path == '/api/getPreferenceValue') {
    return const ServerRoute(ServerRouteKind.wasmOptOut);
  }
  // Extension iframe assets. Checked before the service-worker and asset
  // rules so the `<id>/<rel>` split survives.
  if (path.startsWith(extensionUrlPrefix) &&
      !path.endsWith('/flutter_service_worker.js')) {
    return ServerRoute(
        ServerRouteKind.extensionAsset, path.substring(extensionUrlPrefix.length));
  }
  if (path == '/api/ping') return const ServerRoute(ServerRouteKind.apiPing);
  if (path == '/api/serveAvailableExtensions') {
    return const ServerRoute(ServerRouteKind.serveExtensions);
  }
  if (path == '/api/extensionEnabledState') {
    return const ServerRoute(ServerRouteKind.extensionEnabledState);
  }
  // Neutralize DevTools' service worker: a stale SW (e.g. cached from an
  // earlier wasm load) otherwise serves stale assets forever and the page
  // stays blank. Ours unregisters itself, so this server — fast, on
  // loopback — is always the source of truth.
  if (path.endsWith('/flutter_service_worker.js')) {
    return const ServerRoute(ServerRouteKind.killServiceWorker);
  }
  if (path.startsWith('/api/')) return const ServerRoute(ServerRouteKind.apiOther);
  var rel = path.startsWith('/') ? path.substring(1) : path;
  if (rel.isEmpty) rel = 'index.html';
  final last = rel.split('/').last;
  // Paths without a file extension are client-side DevTools routes (e.g.
  // /logging) — serve the SPA shell.
  if (!last.contains('.')) rel = 'index.html';
  return ServerRoute(ServerRouteKind.devtoolsAsset, '$assetPrefix/$rel');
}

String mimeFor(String path) {
  final ext = path.split('.').last.toLowerCase();
  const map = {
    'html': 'text/html',
    'js': 'text/javascript',
    'mjs': 'text/javascript',
    'css': 'text/css',
    'wasm': 'application/wasm',
    'json': 'application/json',
    'png': 'image/png',
    'ico': 'image/x-icon',
    'svg': 'image/svg+xml',
    'otf': 'font/otf',
    'ttf': 'font/ttf',
    'woff2': 'font/woff2',
    'txt': 'text/plain',
  };
  return map[ext] ?? 'application/octet-stream';
}
