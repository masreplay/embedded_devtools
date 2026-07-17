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

No guards are needed: `start()` no-ops and the overlay renders nothing in
release. If you want the AOT compiler to drop the code entirely, guard with
**`!kReleaseMode`**:

```dart
if (!kReleaseMode) EmbeddedDevTools.start();
```

> ⚠️ **Don't guard with `kDebugMode`.** In the Flutter SDK it's defined as
> `!kReleaseMode && !kProfileMode` — so it's **false in profile builds**, and
> would silently disable DevTools in the very build you hand to QA.
> `kReleaseMode` is a compile-time const too, so release still tree-shakes it.

---

## Extensions

> **Read this before relying on extensions.** They are discovered, listed, and
> their UI renders on-device — but most popular extensions **cannot function**
> here, and it isn't a bug we can fix. `provider`, `riverpod`,
> `shared_preferences` and `get_it` all inspect your app through **expression
> evaluation**, which needs a compilation service that only exists when a
> computer runs `flutter run`. See [Extensions and eval](#extensions-and-eval).
>
> Everything else — Inspector, Performance, CPU, Memory, Network, Logging —
> works normally, and none of it needs eval.

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

## Extensions and eval

Extension support is real and the plumbing is verified end to end:

| | Status |
|---|---|
| Discovered from `package_config.json` and bundled | ✅ |
| Listed in DevTools' Extensions dialog, Enabled | ✅ |
| Shown as screens in DevTools' menu, with their icons | ✅ |
| Extension iframe loads and its UI renders | ✅ |
| Extension inspects your app **via eval** | ❌ **impossible — see below** |

**Expression evaluation cannot work without a computer.** The Dart VM does not
compile Dart source. When DevTools evaluates an expression, the VM delegates to
`_compileExpression` — a service registered by the **`frontend_server` that
`flutter run` starts on your machine**. A standalone app has no Flutter tool
attached, so the VM answers:

```
_compileExpression: No compilation service available; cannot evaluate from source.
```

This is by construction, not a bug, and it applies in **debug builds too** — it
has nothing to do with `kDebugMode` or build modes at all.

`provider`, `riverpod`, `shared_preferences` and `get_it` all read your app's
state by evaluating expressions (e.g. `shared_preferences` evaluates
`SharedPreferencesDevToolsExtensionData().…`). Their panels will render and then
report a connection error — `provider` says *"DevTools failed to connect with
package:provider"*, which is misleading: your provider version is fine.

An extension that talks to its package through **registered service extensions**
(`ext.<name>.*`) rather than eval would work here — the transport is a plain
websocket proxy with no filtering, and all 71 of the app's service extensions
are visible through it. We just don't know of a popular one that does.

DevTools' own eval-dependent surfaces (the evaluation console, watch
expressions) are unavailable for the same reason. Everything else is unaffected.

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
