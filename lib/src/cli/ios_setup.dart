// iOS project setup performed by `dart run embedded_devtools:init`.
//
// The in-app WebView loads the DevTools server over plain http on loopback.
// WKWebView is subject to App Transport Security, which denies cleartext by
// default — the iOS analogue of Android's network security config.
//
// `NSAllowsLocalNetworking` permits loopback and local-network http *only*;
// arbitrary internet cleartext stays blocked. Unlike `NSAllowsArbitraryLoads`
// it needs no App Store review justification.
import 'dart:io';

const _plistPath = 'ios/Runner/Info.plist';
const _atsKey = 'NSAppTransportSecurity';

const _atsSnippet = '''
	<!-- Added by embedded_devtools: lets the in-app DevTools WebView reach the
	     embedded server over plain http on loopback. Local/loopback only —
	     cleartext to the internet stays blocked. -->
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
''';

/// Wires up the iOS project. Returns true if the project looks iOS-y and setup
/// succeeded (or was already done).
bool setupIos() {
  final plist = File(_plistPath);
  if (!plist.existsSync()) {
    stdout.writeln('• No $_plistPath — skipping iOS setup.');
    return true;
  }

  final content = plist.readAsStringSync();
  if (content.contains(_atsKey)) {
    stdout.writeln('• $_plistPath already sets $_atsKey — left as is.\n'
        '  Make sure it permits cleartext to 127.0.0.1, or the DevTools tab\n'
        '  will fail to load.');
    return true;
  }

  // Insert before the plist's closing </dict>.
  final close = content.lastIndexOf('</dict>');
  if (close == -1) {
    stderr.writeln('! $_plistPath has no closing </dict> — add this manually:\n'
        '$_atsSnippet');
    return false;
  }
  plist.writeAsStringSync(content.replaceRange(close, close, _atsSnippet));
  stdout.writeln('✓ patched $_plistPath ($_atsKey → NSAllowsLocalNetworking)');
  return true;
}
