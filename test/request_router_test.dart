import 'package:embedded_devtools/embedded_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ws = '/NRPLsCVx3rw=/ws';

  test('vm ws path routes to the proxy', () {
    expect(routeRequest(ws, vmWsPath: ws).kind, ServerRouteKind.vmWebSocket);
  });

  test('/qa routes to the landing page', () {
    expect(routeRequest('/qa', vmWsPath: ws).kind, ServerRouteKind.landing);
  });

  test('preference api routes to the wasm opt-out', () {
    expect(routeRequest('/api/getPreferenceValue', vmWsPath: ws).kind,
        ServerRouteKind.wasmOptOut);
  });

  test('service worker is neutralized', () {
    expect(routeRequest('/flutter_service_worker.js', vmWsPath: ws).kind,
        ServerRouteKind.killServiceWorker);
  });

  test('root serves the devtools index', () {
    final r = routeRequest('/', vmWsPath: ws);
    expect(r.kind, ServerRouteKind.devtoolsAsset);
    expect(r.assetKey, 'assets/devtools/index.html');
  });

  test('asset path maps to an asset key', () {
    expect(routeRequest('/main.dart.js', vmWsPath: ws).assetKey,
        'assets/devtools/main.dart.js');
  });

  test('nested asset path', () {
    expect(routeRequest('/canvaskit/canvaskit.wasm', vmWsPath: ws).assetKey,
        'assets/devtools/canvaskit/canvaskit.wasm');
  });

  test('SPA deep link falls back to the index', () {
    expect(routeRequest('/logging', vmWsPath: ws).assetKey,
        'assets/devtools/index.html');
  });

  group('devtools server api', () {
    test('ping is answered so DevTools detects a server', () {
      expect(routeRequest('/api/ping', vmWsPath: ws).kind,
          ServerRouteKind.apiPing);
    });

    test('extension discovery', () {
      expect(routeRequest('/api/serveAvailableExtensions', vmWsPath: ws).kind,
          ServerRouteKind.serveExtensions);
    });

    test('extension enabled state', () {
      expect(routeRequest('/api/extensionEnabledState', vmWsPath: ws).kind,
          ServerRouteKind.extensionEnabledState);
    });

    test('unknown api calls are answered benignly, not treated as assets', () {
      expect(routeRequest('/api/getSurveyShownCount', vmWsPath: ws).kind,
          ServerRouteKind.apiOther);
    });
  });

  group('extension assets', () {
    test('iframe entrypoint keeps its id and relative path', () {
      final r = routeRequest('/devtools_extensions/provider_6.1.5/index.html',
          vmWsPath: ws);
      expect(r.kind, ServerRouteKind.extensionAsset);
      expect(r.assetKey, 'provider_6.1.5/index.html');
    });

    test('nested extension asset', () {
      final r = routeRequest(
          '/devtools_extensions/provider_6.1.5/assets/fonts/a.otf',
          vmWsPath: ws);
      expect(r.assetKey, 'provider_6.1.5/assets/fonts/a.otf');
    });

    test("an extension's service worker is neutralized too", () {
      expect(
          routeRequest(
                  '/devtools_extensions/provider_6.1.5/flutter_service_worker.js',
                  vmWsPath: ws)
              .kind,
          ServerRouteKind.killServiceWorker);
    });
  });

  group('extension info', () {
    test('identifier matches the path segment DevTools requests', () {
      const e = DevToolsExtensionInfo(
          name: 'Provider', version: '6.1.5', materialIconCodePoint: 0xe55b);
      expect(e.identifier, 'provider_6.1.5');
      expect(e.assetRoot, 'assets/devtools_extensions/provider_6.1.5');
    });

    test('parses a hex icon code point written as a quoted string', () {
      final e = DevToolsExtensionInfo.fromJson(const {
        'name': 'provider',
        'version': '6.1.5',
        'materialIconCodePoint': '0xe55b',
      });
      expect(e.materialIconCodePoint, 0xe55b);
      expect(e.requiresConnection, isTrue);
    });

    test('devtools json carries the fields the frontend requires', () {
      const e = DevToolsExtensionInfo(
          name: 'provider', version: '6.1.5', materialIconCodePoint: 0xe55b);
      final json = e.toDevToolsJson();
      expect(json['name'], 'provider');
      expect(json['version'], '6.1.5');
      expect(json['requiresConnection'], 'true');
      expect(json['extensionAssetsPath'], isNotEmpty);
    });
  });

  test('mime types', () {
    expect(mimeFor('a.js'), 'text/javascript');
    expect(mimeFor('a.wasm'), 'application/wasm');
    expect(mimeFor('a.html'), 'text/html');
    expect(mimeFor('a.json'), 'application/json');
    expect(mimeFor('a.png'), 'image/png');
    expect(mimeFor('a.otf'), 'font/otf');
    expect(mimeFor('weird.xyz'), 'application/octet-stream');
  });

  test('wsPath derives from the VM service http uri', () {
    final info = VmServiceInfo(Uri.parse('http://127.0.0.1:43333/NRPLsCVx3rw=/'));
    expect(info.wsPath, '/NRPLsCVx3rw=/ws');
    expect(info.port, 43333);
  });
}
