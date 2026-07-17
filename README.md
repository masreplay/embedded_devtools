# embedded_devtools

**Flutter DevTools, embedded in your app.** Open the full DevTools suite on a
real device — no computer, no cable, no IDE.

The app serves the DevTools web build itself and proxies its own VM service, so
a tester with nothing but an APK gets the Inspector, Performance, CPU Profiler,
Memory, Network, Logging — and every DevTools extension your dependencies ship.

## Setup

```yaml
dependencies:
  embedded_devtools: ^0.1.0
```

Bundle the web assets (re-run whenever dependencies change — same cadence as
`pub get`):

```sh
dart run embedded_devtools:bundle
```

That copies DevTools out of *your* Flutter SDK, discovers every dependency that
ships a DevTools extension, copies their prebuilt builds, and writes the
`assets:` entries into your `pubspec.yaml` for you.

Then start it and add the bubble:

```dart
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
```

### Android

The in-app WebView loads the server over plain http on loopback, which Android
blocks by default in profile/release builds. Add a localhost-scoped exception —
`android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">127.0.0.1</domain>
        <domain includeSubdomains="true">localhost</domain>
    </domain-config>
</network-security-config>
```

and reference it from `<application>` in `AndroidManifest.xml`:

```xml
<application android:networkSecurityConfig="@xml/network_security_config" ...>
```

Every other domain keeps the platform default.

## Use it

Build with `--profile`, install, launch, tap the bubble.

```sh
flutter build apk --profile
```

## Extensions

Anything your app already depends on that ships a DevTools extension shows up
under DevTools' own Extensions area — nothing to register, no code to write:

```yaml
dependencies:
  embedded_devtools: ^0.1.0
  provider: ^6.1.5           # ships a DevTools extension
  shared_preferences: ^2.5.5 # ships a DevTools extension
```

```sh
dart run embedded_devtools:bundle
```
```
DevTools: 412 files (81.4 MB)
  provider 6.1.5 → provider_6.1.5 (1.9 MB)
  shared_preferences 2.5.5 → shared_preferences_2.5.5 (1.8 MB)

Extensions: 2 bundled.
pubspec.yaml: wrote 27 asset entries.
```

On desktop, DevTools' *server* finds extensions by reading your
`package_config.json` and serving each package's prebuilt
`extension/devtools/build/`. A device has neither that server nor a pub cache,
so `bundle` does the same discovery at build time and the embedded server
replays the result. Extensions ship prebuilt, so nothing is compiled — it's a
file copy.

## Hard limits (physics, not bugs)

- **Release builds have no VM service.** The AOT product engine compiles it
  out, so there is nothing for DevTools to attach to. `EmbeddedDevTools.start()`
  is a no-op in release, and the overlay renders nothing. Use `--profile`: it's
  the "QA release" — release-grade performance with the VM service intact.
  (This is also why iOS TestFlight is out: it only ships release builds.)
- **Assets are large.** The DevTools build is ~80 MB. Put this behind a QA
  flavor rather than shipping it to production.
- **Backgrounding freezes the server on Android 12+** (cached-app freezer).
  `EmbeddedDevTools.start(keepAlive: true)` — the default — runs a foreground
  service to mitigate it. The in-app WebView sidesteps it entirely: nothing is
  backgrounded.
- **The wasm DevTools build can't be used.** It needs SharedArrayBuffer via
  cross-origin isolation, which a plain-http loopback server can't grant. The
  server always selects the dart2js+canvaskit build, which renders everywhere.
