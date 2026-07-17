# embedded_devtools

**Flutter DevTools, embedded in your app.**

Open the full DevTools suite on a real device — no computer, no cable, no IDE.
Hand a tester an APK and they get the Inspector, Performance, CPU Profiler,
Memory, Network and Logging, plus every DevTools extension your dependencies
ship. All of it inside the app.

The app serves the DevTools web build from its own assets and proxies its own
VM service, so nothing outside the phone is involved.

---

## Install

```yaml
dependencies:
  embedded_devtools: ^0.1.0
```

```sh
dart run embedded_devtools:init
```

That's the setup. `init` wires up Android, copies DevTools out of your Flutter
SDK, finds every extension your dependencies ship, and writes your pubspec's
`assets:` entries.

Then add two lines to `main.dart`:

```dart
import 'package:embedded_devtools/embedded_devtools.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  EmbeddedDevTools.start();                       // ← 1

  runApp(MaterialApp(
    home: const HomePage(),
    builder: (context, child) =>
        EmbeddedDevToolsOverlay(child: child ?? const SizedBox()),  // ← 2
  ));
}
```

Build, install, tap the bubble:

```sh
flutter build apk --profile
```

> **Use `--profile`.** Release builds have no Dart VM service — the AOT product
> engine compiles it out — so DevTools has nothing to attach to. Profile is the
> "QA release": release-grade performance with the VM service intact.

---

## Extensions come along for free

> **Status: partially working.** Extensions are discovered, listed in DevTools'
> Extensions dialog, and their UI renders on-device. But an extension that
> talks back to its own package at runtime (e.g. `provider` listing your
> providers) currently fails to connect — see
> [Known issues](#known-issues). The plumbing works; the last hop doesn't yet.

Anything you already depend on that ships a DevTools extension appears under
DevTools' own **Extensions** area. Nothing to register, no code to write:

```yaml
dependencies:
  embedded_devtools: ^0.1.0

  provider: ^6.1.5             # ships a DevTools extension
  shared_preferences: ^2.5.5   # ships a DevTools extension
```

```sh
dart run embedded_devtools:bundle
```

```
✓ DevTools: 434 files (80.0 MB)
    provider 0.0.1 → provider_0.0.1 (7.3 MB)
    shared_preferences 1.0.0 → shared_preferences_1.0.0 (7.2 MB)
✓ Extensions: 2 bundled
✓ pubspec.yaml: wrote 47 asset entries
```

Add a package → re-run `bundle` → it's there. Remove it → it's gone. This
package never names any extension; the list is discovered and written to a
manifest at build time.

> The version shown is the **extension's** version from its
> `extension/devtools/config.yaml`, not the package's — provider 6.1.5 ships
> extension `0.0.1`. DevTools identifies extensions as `<name>_<extension
> version>`, so that's what the asset folders use.

---

## Commands

| Command | When |
|---|---|
| `dart run embedded_devtools:init` | Once, at setup. Android wiring + assets. |
| `dart run embedded_devtools:bundle` | Whenever dependencies change — same cadence as `pub get`. |

Run both with the same SDK you build with (`fvm dart run …` if you use FVM):
DevTools is copied out of *that* SDK, so your app always ships the DevTools
version matching your Flutter.

---

## How it works

On your laptop, DevTools doesn't find extensions by itself — a **DevTools
server** does, by reading your project's `package_config.json` and serving each
package's prebuilt `extension/devtools/build/` off disk.

A phone has no such server and no pub cache. So:

- **`bundle`** performs that same discovery at *build* time and copies the
  results into your app's assets. Extensions ship prebuilt, so nothing is
  compiled — it's a file copy. Every extension's identical ~37 MB CanvasKit is
  skipped and shared from the one DevTools copy.
- **`EmbeddedDevTools.start()`** runs a small HTTP server in the app that
  serves those assets, proxies the app's VM service over a websocket, and
  answers the handful of DevTools-server API calls the frontend needs —
  including extension discovery.
- **`EmbeddedDevToolsOverlay`** shows a draggable bubble that opens DevTools in
  an in-app WebView, pointed at that server.

---

## API

```dart
EmbeddedDevTools.start({
  int port = 9200,          // first free port in [port, port + 10)
  bool keepAlive = true,    // Android foreground service; see below
});

EmbeddedDevTools.server;    // DevToolsServerHandle? — urls, extensions, port

EmbeddedDevToolsOverlay(child: child);
```

The overlay's **Links** tab also lists a LAN URL per network interface, if you'd
rather open DevTools in the phone's browser or from a PC on the same WiFi.

---

> Working on this? Read **[docs/CONTEXT.md](docs/CONTEXT.md)** first — it has the
> reverse-engineered DevTools server contract, what's proven vs assumed, and the
> traps that already cost time.

## Known issues

**Extensions render but can't connect to their package.** Verified on an
Android emulator with `provider` and `shared_preferences`:

| | Status |
|---|---|
| Discovered from `package_config.json` and bundled | ✅ |
| Listed in DevTools' Extensions dialog, Enabled | ✅ |
| Shown as screens in DevTools' menu, with icons | ✅ |
| Extension iframe loads and its UI renders | ✅ |
| Extension talks to its package in the running app | ❌ |

`provider`'s extension reports *"DevTools failed to connect with
package:provider"*. This happens in **both profile and debug** builds, so it
isn't the usual `kDebugMode` gating.

Current lead: DevTools reports **"Flutter native (profile build)"** even for a
debug build when connected through this server's websocket proxy. If DevTools
misidentifies the build type it disables the evaluation-based features an
extension like `provider` relies on. Unconfirmed.

Everything else — Inspector, Performance, CPU, Memory, Network, Logging — works
normally.

## Hard limits (physics, not bugs)

- **Release builds have no VM service.** `EmbeddedDevTools.start()` is a no-op
  in release and the overlay renders nothing. Use `--profile`. This is also why
  iOS TestFlight is out: it only ships release builds.
- **The assets are large** (~80 MB for DevTools, plus a few MB per extension).
  Put this behind a QA flavor rather than shipping it to production.
- **Android 12+ freezes backgrounded apps** (the cached-app freezer), which
  stops the server answering while the phone's browser is in front.
  `start(keepAlive: true)` — the default — runs a foreground service to
  mitigate it. The in-app WebView sidesteps the problem entirely: nothing is
  backgrounded.
- **The wasm DevTools build can't be used.** It needs `SharedArrayBuffer` via
  cross-origin isolation, which a plain-http loopback server cannot grant — it
  renders a blank page. The server always selects the dart2js + CanvasKit
  build, which works everywhere.

---

## What `init` changes in your project

Nothing surprising, and nothing that reaches production:

- `android/app/src/main/res/xml/network_security_config.xml` — permits cleartext
  **to 127.0.0.1 and localhost only**; every other domain keeps the platform
  default.
- `android/app/src/{debug,profile}/AndroidManifest.xml` — reference that config.
  Deliberately **not** `src/main`, so the exception cannot exist in a release
  build.
- `pubspec.yaml` — a generated `assets:` block between marker comments. Safe to
  re-run; it rewrites only that block.

If your app already sets its own `networkSecurityConfig`, `init` won't fight the
manifest merger — it says so and leaves your config alone. Make sure it permits
cleartext to `127.0.0.1`, or the DevTools tab will show
`ERR_CLEARTEXT_NOT_PERMITTED`.
