// Bundles everything the embedded DevTools server needs into the app's assets:
//
//   1. the DevTools web build, taken from the Flutter SDK running this script
//   2. every DevTools extension your dependencies ship, discovered the same
//      way DevTools' own server does it — by reading .dart_tool/package_config.json
//   3. a manifest the server reads at runtime to advertise those extensions
//   4. the matching `assets:` entries, written into pubspec.yaml for you
//
// Run from the app directory, using the same Flutter SDK you build with:
//
//   dart run embedded_devtools:bundle
//
// Re-run it whenever your dependencies change — same cadence as `pub get`.
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const _devtoolsDest = 'assets/devtools';
const _extensionsDest = 'assets/devtools_extensions';
const _beginMarker = '    # BEGIN embedded_devtools (generated — do not edit)';
const _endMarker = '    # END embedded_devtools';

void main(List<String> args) {
  final dirs = <String>{};

  final devtoolsCount = _copyDevTools(dirs);
  if (devtoolsCount == 0) exit(1);

  final extensions = _bundleExtensions(dirs);
  _writeManifest(extensions);

  _patchPubspec(dirs);
  stdout.writeln('\nDone. Rebuild the app to pick up the new assets.');
}

// ---------------------------------------------------------------- DevTools

/// Copies the DevTools web build out of the Flutter SDK running this script.
int _copyDevTools(Set<String> dirs) {
  final dartBin = File(Platform.resolvedExecutable).parent; // dart-sdk/bin
  final src = Directory('${dartBin.path}/resources/devtools');
  if (!src.existsSync()) {
    stderr.writeln('DevTools assets not found at ${src.path}.\n'
        'Run with the Flutter-bundled Dart, e.g. '
        '`fvm dart run embedded_devtools:bundle`.');
    return 0;
  }
  final dest = Directory(_devtoolsDest);
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  final result = _copyTree(src, dest, dirs);
  stdout.writeln('DevTools: ${result.files} files (${_mb(result.bytes)})');
  return result.files;
}

// -------------------------------------------------------------- Extensions

/// Discovers every dependency shipping `extension/devtools/config.yaml` with a
/// prebuilt `build/`, and copies each build into the app's assets.
///
/// This mirrors what DevTools' server does at runtime on desktop; a device has
/// no pub cache, so we do it at build time instead.
List<Map<String, Object?>> _bundleExtensions(Set<String> dirs) {
  final dest = Directory(_extensionsDest);
  if (dest.existsSync()) dest.deleteSync(recursive: true);

  final packages = _readPackageConfig();
  if (packages.isEmpty) {
    stdout.writeln('\nNo .dart_tool/package_config.json — run `pub get` first.');
    return [];
  }

  final found = <Map<String, Object?>>[];
  for (final entry in packages.entries) {
    final root = entry.value;
    final configFile = File('${root.toFilePath()}extension/devtools/config.yaml');
    final buildDir = Directory('${root.toFilePath()}extension/devtools/build');
    if (!configFile.existsSync() || !buildDir.existsSync()) continue;

    final Map<String, Object?> config;
    try {
      final yaml = loadYaml(configFile.readAsStringSync());
      if (yaml is! YamlMap) continue;
      config = Map<String, Object?>.from(yaml);
    } catch (e) {
      stderr.writeln('  skipped ${entry.key}: unreadable config.yaml ($e)');
      continue;
    }

    final name = config['name']?.toString();
    final version = config['version']?.toString();
    if (name == null || version == null) {
      stderr.writeln('  skipped ${entry.key}: config.yaml lacks name/version');
      continue;
    }
    final id = '${name.toLowerCase()}_$version';

    // Skip canvaskit: every extension ships an identical ~37 MB copy, and the
    // server serves them all from the shared DevTools build instead.
    final result = _copyTree(buildDir, Directory('$_extensionsDest/$id'), dirs,
        skipDir: 'canvaskit');
    stdout.writeln('  $name $version → $id (${_mb(result.bytes)})');

    found.add({
      'name': name,
      'version': version,
      'materialIconCodePoint': config['materialIconCodePoint']?.toString() ?? '0xe051',
      'issueTracker': config['issueTracker']?.toString() ?? '',
      'requiresConnection': config['requiresConnection'] != false,
    });
  }

  stdout.writeln(found.isEmpty
      ? '\nExtensions: none found in your dependencies.'
      : '\nExtensions: ${found.length} bundled.');
  return found;
}

/// Writes the manifest the runtime reads to advertise extensions to DevTools.
void _writeManifest(List<Map<String, Object?>> extensions) {
  File('$_extensionsDest/manifest.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(extensions));
}

/// Maps package name → resolved root directory URI (from package_config.json).
Map<String, Uri> _readPackageConfig() {
  final file = File('.dart_tool/package_config.json');
  if (!file.existsSync()) return {};
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } catch (_) {
    return {};
  }
  if (decoded is! Map || decoded['packages'] is! List) return {};
  final base = file.absolute.parent.uri; // .dart_tool/
  final out = <String, Uri>{};
  for (final p in decoded['packages'] as List) {
    if (p is! Map) continue;
    final name = p['name']?.toString();
    final rootUri = p['rootUri']?.toString();
    if (name == null || rootUri == null) continue;
    var uri = base.resolve(rootUri);
    if (!uri.path.endsWith('/')) uri = uri.replace(path: '${uri.path}/');
    out[name] = uri;
  }
  return out;
}

// ------------------------------------------------------------------ pubspec

/// Rewrites the generated `assets:` block in pubspec.yaml, in place.
void _patchPubspec(Set<String> dirs) {
  final entries = (dirs.toList()..sort()).map((d) => '    - $d/').toList();
  final block = [_beginMarker, ...entries, _endMarker];

  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('\nNo pubspec.yaml here. Add these entries manually:');
    stdout.writeln(block.join('\n'));
    return;
  }
  final lines = file.readAsLinesSync();

  final begin = lines.indexWhere((l) => l.trimRight() == _beginMarker);
  final end = lines.indexWhere((l) => l.trimRight() == _endMarker);
  if (begin != -1 && end > begin) {
    lines.replaceRange(begin, end + 1, block);
    file.writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln('\npubspec.yaml: updated ${entries.length} asset entries.');
    return;
  }

  final flutterIdx = lines.indexWhere((l) => l.trimRight() == 'flutter:');
  if (flutterIdx == -1) {
    stderr.writeln('\nNo top-level `flutter:` section in pubspec.yaml. '
        'Add these entries manually:');
    stdout.writeln(block.join('\n'));
    return;
  }
  // Find an `assets:` key inside the flutter block (2-space indent).
  var assetsIdx = -1;
  for (var i = flutterIdx + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    // Left the flutter block.
    if (!line.startsWith(' ')) break;
    if (line.trimRight() == '  assets:') {
      assetsIdx = i;
      break;
    }
  }
  if (assetsIdx == -1) {
    lines.insertAll(flutterIdx + 1, ['  assets:', ...block]);
  } else {
    lines.insertAll(assetsIdx + 1, block);
  }
  file.writeAsStringSync('${lines.join('\n')}\n');
  stdout.writeln('\npubspec.yaml: wrote ${entries.length} asset entries.');
}

// ------------------------------------------------------------------- utils

class _CopyResult {
  const _CopyResult(this.files, this.bytes);
  final int files;
  final int bytes;
}

/// Copies [src] into [dest], recording each populated directory (as a path
/// relative to cwd) in [dirs] for the pubspec — Flutter's directory asset
/// entries are not recursive, so every level needs its own line.
_CopyResult _copyTree(Directory src, Directory dest, Set<String> dirs,
    {String? skipDir}) {
  var files = 0;
  var bytes = 0;
  final cwd = '${Directory.current.path}/';
  for (final entity in src.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = entity.path.substring(src.path.length + 1);
    if (entity.path.endsWith('.map')) continue;
    if (skipDir != null && rel.split('/').first == skipDir) continue;
    final out = File('${dest.path}/$rel')..createSync(recursive: true);
    entity.copySync(out.path);
    files++;
    bytes += entity.lengthSync();
    var dir = out.parent.path;
    if (dir.startsWith(cwd)) dir = dir.substring(cwd.length);
    dirs.add(dir);
  }
  return _CopyResult(files, bytes);
}

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
