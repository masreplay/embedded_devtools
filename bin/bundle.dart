// Refreshes the bundled assets. Run from the app directory, using the same
// Flutter SDK you build with:
//
//   dart run embedded_devtools:bundle
//
// Copies the DevTools web build from your Flutter SDK, discovers every
// dependency that ships a DevTools extension and copies its prebuilt build,
// writes the runtime manifest, and updates your pubspec's `assets:` block.
//
// Re-run whenever dependencies change — the same cadence as `pub get`. For
// first-time setup (including Android wiring), use `init` instead.
import 'dart:io';

import 'package:embedded_devtools/src/cli/bundle.dart';

void main(List<String> args) {
  if (!runBundle()) exit(1);
  stdout.writeln('\nDone. Rebuild the app to pick up the new assets.');
}
