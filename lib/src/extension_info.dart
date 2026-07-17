/// Where the `bundle` CLI writes the list of extensions it discovered.
const extensionManifestAssetKey = 'assets/devtools_extensions/manifest.json';

/// Root asset directory holding every bundled extension's web build, at
/// `<extensionAssetPrefix>/<identifier>/...`.
const extensionAssetPrefix = 'assets/devtools_extensions';

/// A DevTools extension bundled into this app, as discovered by
/// `dart run embedded_devtools:bundle` and recorded in the asset manifest.
///
/// On a desktop setup, DevTools' *server* discovers extensions by reading the
/// app's `package_config.json` and serving each package's prebuilt
/// `extension/devtools/build/`. A device has neither that server nor the pub
/// cache, so the CLI does the same discovery at build time and this server
/// replays the result.
class DevToolsExtensionInfo {
  const DevToolsExtensionInfo({
    required this.name,
    required this.version,
    required this.materialIconCodePoint,
    this.issueTracker = '',
    this.requiresConnection = true,
  });

  factory DevToolsExtensionInfo.fromJson(Map<String, Object?> json) {
    final icon = json['materialIconCodePoint'];
    return DevToolsExtensionInfo(
      name: json['name']! as String,
      version: json['version']! as String,
      materialIconCodePoint: switch (icon) {
        int() => icon,
        // config.yaml usually quotes it, e.g. '0xe55b'.
        String() => int.tryParse(icon.replaceFirst('0x', ''), radix: 16) ?? 0,
        _ => 0,
      },
      issueTracker: json['issueTracker'] as String? ?? '',
      requiresConnection: switch (json['requiresConnection']) {
        final bool b => b,
        'false' => false,
        _ => true,
      },
    );
  }

  /// Extension package name, from its `extension/devtools/config.yaml`.
  final String name;

  /// Extension version, from its `config.yaml`.
  final String version;

  /// Material icon code point shown as the extension's tab icon.
  final int materialIconCodePoint;

  final String issueTracker;
  final bool requiresConnection;

  /// The path segment DevTools uses for the extension iframe:
  /// `<name lowercased>_<version>`. Must match DevTools' own identifier.
  String get identifier => '${name.toLowerCase()}_$version';

  /// Asset-bundle key prefix for this extension's files.
  String get assetRoot => '$extensionAssetPrefix/$identifier';

  Map<String, Object?> toJson() => {
        'name': name,
        'version': version,
        'materialIconCodePoint': materialIconCodePoint,
        'issueTracker': issueTracker,
        'requiresConnection': requiresConnection,
      };

  /// The shape DevTools' `serveAvailableExtensions` API returns per extension
  /// (mirrors its `DevToolsExtensionConfig.toJson`).
  Map<String, Object?> toDevToolsJson() => {
        'name': name,
        'issueTracker': issueTracker,
        'version': version,
        'materialIconCodePoint': materialIconCodePoint,
        'requiresConnection': requiresConnection.toString(),
        // Server-side path in a normal setup; DevTools builds the iframe URL
        // from name+version, so any stable value works here.
        'extensionAssetsPath': assetRoot,
        'devtoolsOptionsUri': 'file:///devtools_options.yaml',
        'isPubliclyHosted': 'false',
        'detectedFromStaticContext': 'false',
      };
}
