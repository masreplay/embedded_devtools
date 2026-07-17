/// Flutter DevTools, embedded in your app.
///
/// The app serves the DevTools web build itself and proxies its own VM
/// service, so the full suite — Inspector, Performance, CPU, Memory, Network,
/// Logging, and any DevTools extensions your dependencies ship — opens on a
/// real device with no computer, no cable and no IDE.
///
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   EmbeddedDevTools.start();
///   runApp(MaterialApp(
///     home: const HomePage(),
///     builder: (context, child) =>
///         EmbeddedDevToolsOverlay(child: child ?? const SizedBox()),
///   ));
/// }
/// ```
///
/// Bundle the web assets once (and again whenever dependencies change):
///
/// ```sh
/// dart run embedded_devtools:bundle
/// ```
///
/// Requires a `--debug` or `--profile` build: release has no VM service.
library;

export 'src/devtools_server.dart'
    show AssetReader, DevToolsServer, DevToolsServerHandle, EmbeddedDevTools;
export 'src/extension_info.dart'
    show DevToolsExtensionInfo, extensionAssetPrefix, extensionManifestAssetKey;
export 'src/overlay.dart' show EmbeddedDevToolsOverlay;
export 'src/server_routes.dart'
    show ServerRoute, ServerRouteKind, mimeFor, routeRequest;
export 'src/vm_service_info.dart' show VmServiceInfo;
