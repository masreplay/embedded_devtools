// One-time setup for embedded_devtools. Run from the app directory:
//
//   dart run embedded_devtools:init
//
// Does everything: Android wiring, DevTools assets, extension discovery, and
// the pubspec entries. Afterwards, `bundle` alone is enough to refresh assets
// when dependencies change.
import 'dart:io';

import 'package:embedded_devtools/src/cli/android_setup.dart';
import 'package:embedded_devtools/src/cli/bundle.dart';
import 'package:embedded_devtools/src/cli/ios_setup.dart';

void main(List<String> args) {
  stdout.writeln('embedded_devtools: setting up\n');

  stdout.writeln('Android');
  setupAndroid();

  stdout.writeln('\niOS');
  setupIos();

  stdout.writeln('\nAssets');
  if (!runBundle()) exit(1);

  stdout.writeln('''

Done. One step left — start it, and add the bubble:

  import 'package:embedded_devtools/embedded_devtools.dart';

  void main() {
    WidgetsFlutterBinding.ensureInitialized();
    EmbeddedDevTools.start();

    runApp(MaterialApp(
      home: const HomePage(),
      builder: (context, child) =>
          EmbeddedDevToolsOverlay(child: child ?? const SizedBox()),
    ));
  }

Then build with --profile (release has no VM service, so DevTools cannot
attach) and tap the bubble:

  flutter build apk --profile

Re-run `dart run embedded_devtools:bundle` whenever your dependencies change.
''');
}
