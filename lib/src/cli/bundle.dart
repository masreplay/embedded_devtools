// Bundling logic shared by `bin/bundle.dart` and `bin/init.dart`.
//
// Nothing here is imported by the runtime library, so it never ships inside an
// app — it only runs under `dart run embedded_devtools:<command>`.
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const devtoolsDest = 'assets/devtools';
const extensionsDest = 'assets/devtools_extensions';
const _beginMarker = '    # BEGIN embedded_devtools (generated — do not edit)';
const _endMarker = '    # END embedded_devtools';

/// Copies DevTools + every discovered extension into the app's assets, writes
/// the runtime manifest, and rewrites the generated `assets:` block.
///
/// Returns true on success.
bool runBundle() {
  final dirs = <String>{};

  if (!_copyDevTools(dirs)) return false;
  final extensions = _bundleExtensions(dirs);
  _writeManifest(extensions);
  // The manifest sits at the root of the extensions dir, which _copyTree never
  // records (it only registers directories it copies files into). Without this
  // the manifest isn't bundled, rootBundle can't read it, and DevTools is told
  // there are no extensions.
  dirs.add(extensionsDest);
  _patchPubspec(dirs);
  return true;
}

// ---------------------------------------------------------------- DevTools

/// Copies the DevTools web build out of the Flutter SDK running this script.
bool _copyDevTools(Set<String> dirs) {
  final dartBin = File(Platform.resolvedExecutable).parent; // dart-sdk/bin
  final src = Directory('${dartBin.path}/resources/devtools');
  if (!src.existsSync()) {
    stderr.writeln('✗ DevTools assets not found at ${src.path}\n'
        '  Run with the Flutter-bundled Dart, e.g.\n'
        '    fvm dart run embedded_devtools:bundle');
    return false;
  }
  final dest = Directory(devtoolsDest);
  if (dest.existsSync()) dest.deleteSync(recursive: true);
  final result = _copyTree(src, dest, dirs);
  stdout.writeln('✓ DevTools: ${result.files} files (${_mb(result.bytes)})');
  return result.files > 0;
}

// -------------------------------------------------------------- Extensions

/// Discovers every dependency shipping `extension/devtools/config.yaml` with a
/// prebuilt `build/`, and copies each build into the app's assets.
///
/// This mirrors what DevTools' server does at runtime on desktop; a device has
/// no pub cache, so we do the same discovery at build time instead.
List<Map<String, Object?>> _bundleExtensions(Set<String> dirs) {
  final dest = Directory(extensionsDest);
  if (dest.existsSync()) dest.deleteSync(recursive: true);

  final packages = _readPackageConfig();
  if (packages.isEmpty) {
    stdout.writeln('! No .dart_tool/package_config.json — run `pub get` first.');
    return [];
  }

  final found = <Map<String, Object?>>[];
  for (final entry in packages.entries) {
    final root = entry.value.toFilePath();
    final configFile = File('${root}extension/devtools/config.yaml');
    final buildDir = Directory('${root}extension/devtools/build');
    if (!configFile.existsSync() || !buildDir.existsSync()) continue;

    final Map<String, Object?> config;
    try {
      final yaml = loadYaml(configFile.readAsStringSync());
      if (yaml is! YamlMap) continue;
      config = Map<String, Object?>.from(yaml);
    } catch (e) {
      stderr.writeln('  ! skipped ${entry.key}: unreadable config.yaml ($e)');
      continue;
    }

    final name = config['name']?.toString();
    final version = config['version']?.toString();
    if (name == null || version == null) {
      stderr.writeln('  ! skipped ${entry.key}: config.yaml lacks name/version');
      continue;
    }
    final id = '${name.toLowerCase()}_$version';

    // Skip canvaskit: every extension ships an identical ~37 MB copy, and the
    // server serves them all from the shared DevTools build instead.
    final result = _copyTree(buildDir, Directory('$extensionsDest/$id'), dirs,
        skipDir: 'canvaskit');

    found.add({
      'name': name,
      'version': version,
      'materialIconCodePoint':
          config['materialIconCodePoint']?.toString() ?? '0xe051',
      'issueTracker': config['issueTracker']?.toString() ?? '',
      'requiresConnection': config['requiresConnection'] != false,
    });
    stdout.writeln('    $name $version → $id (${_mb(result.bytes)})');
  }

  stdout.writeln(found.isEmpty
      ? '✓ Extensions: none found in your dependencies'
      : '✓ Extensions: ${found.length} bundled');
  return found;
}

/// Writes the manifest the runtime reads to advertise extensions to DevTools.
void _writeManifest(List<Map<String, Object?>> extensions) {
  File('$extensionsDest/manifest.json')
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
    stderr.writeln('✗ No pubspec.yaml here. Add these entries manually:');
    stdout.writeln(block.join('\n'));
    return;
  }
  final lines = file.readAsLinesSync();

  final begin = lines.indexWhere((l) => l.trimRight() == _beginMarker);
  final end = lines.indexWhere((l) => l.trimRight() == _endMarker);
  if (begin != -1 && end > begin) {
    lines.replaceRange(begin, end + 1, block);
    file.writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln('✓ pubspec.yaml: updated ${entries.length} asset entries');
    return;
  }

  final flutterIdx = lines.indexWhere((l) => l.trimRight() == 'flutter:');
  if (flutterIdx == -1) {
    stderr.writeln('✗ No top-level `flutter:` section in pubspec.yaml. '
        'Add these entries manually:');
    stdout.writeln(block.join('\n'));
    return;
  }
  // Find an `assets:` key inside the flutter block (2-space indent).
  var assetsIdx = -1;
  for (var i = flutterIdx + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) break; // left the flutter block
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
  stdout.writeln('✓ pubspec.yaml: wrote ${entries.length} asset entries');
}

// ------------------------------------------------------------------- utils

class _CopyResult {
  const _CopyResult(this.files, this.bytes);
  final int files;
  final int bytes;
}

/// Copies [src] into [dest], recording each populated directory (relative to
/// cwd) in [dirs] for the pubspec — Flutter's directory asset entries are not
/// recursive, so every level needs its own line.
_CopyResult _copyTree(Directory src, Directory dest, Set<String> dirs,
    {String? skipDir}) {
  var files = 0;
  var bytes = 0;
  final cwd = '${Directory.current.path}/';
  for (final entity in src.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (entity.path.endsWith('.map')) continue;
    final rel = entity.path.substring(src.path.length + 1);
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
