# Project context

Working notes for continuing development. Covers what's built, what's *proven*
vs *assumed*, the reverse-engineered DevTools server contract, and the traps
that already cost time. Written 2026-07-17.

---

## 1. What this is

`embedded_devtools` serves the full Flutter DevTools web build **from inside the
app** and proxies the app's **own VM service**, so DevTools opens on a real
device with no computer, cable or IDE. A QA tester with only an APK gets the
Inspector, Performance, CPU, Memory, Network, Logging — plus any DevTools
extensions the app's dependencies ship.

It was extracted from the `auto_route_devtools` monorepo (where it lived as
`navigation_devtools_qa`). **It is deliberately standalone and must stay that
way**: it knows nothing about navigation, routing, or any specific extension.
The extension list comes from a generated asset manifest, never from code.

The navigation extension still lives in `auto_route_devtools` and is just one
more extension this package can discover — no special casing. Do not add
dependencies on it.

---

## 2. Status

| Capability | Status |
|---|---|
| Serve DevTools from app assets | ✅ verified on device |
| Proxy the app's VM service (websocket) | ✅ verified |
| Full DevTools renders in in-app WebView | ✅ verified |
| Inspector / Performance / CPU / Memory / Network / Logging | ✅ verified (Network captures live traffic) |
| `init` / `bundle` CLIs (discovery, manifest, pubspec, Android) | ✅ verified, idempotent |
| Extensions discovered + listed in DevTools' Extensions dialog | ✅ verified (provider, shared_preferences) |
| Extensions appear as DevTools screens with icons | ✅ verified |
| Extension iframe loads and renders its UI | ✅ verified |
| **Extension inspects the app via eval** | ❌ **impossible — see §6** |
| Excluding the ~94 MB assets from production builds | ❓ untested — see §7 |

Repo: https://github.com/masreplay/embedded_devtools (public, MIT).
**Not published to pub.dev** yet — versions there are permanent, so publish only
once you're happy the eval limitation (§6) is stated honestly in the README.

---

## 3. Architecture

```
lib/
  embedded_devtools.dart      public API barrel
  src/
    devtools_server.dart      EmbeddedDevTools.start(), DevToolsServer, ws proxy,
                              DevTools-server API impersonation, extension assets
    server_routes.dart        pure path → ServerRouteKind classification (unit-tested)
    extension_info.dart       DevToolsExtensionInfo; manifest keys; identifier rule
    overlay.dart              bubble → sheet: [DevTools WebView] [Links]
    landing_page.dart         the /qa page (browser entry point)
    vm_service_info.dart      Service.getInfo() → ws path
    cli/
      bundle.dart             SDK copy + extension discovery + manifest + pubspec
      android_setup.dart      network security config + debug/profile manifests
bin/
  init.dart                   one-time setup  = android_setup + bundle
  bundle.dart                 refresh assets  = bundle only
android/                      KeepAliveService foreground service (Android 12+ freezer)
```

`lib/src/cli/` is **never imported by the runtime library**, so it doesn't ship
inside apps. Keep it that way.

### Runtime flow
1. `EmbeddedDevTools.start()` — binds first free port in `[9200, 9210)`,
   discovers the VM service, reads the extension manifest asset, starts a
   foreground service (Android).
2. `EmbeddedDevToolsOverlay` — bubble → WebView pointed at
   `http://127.0.0.1:<port>/?ide=EmbeddedDevTools&uri=<ws>&compiler=js`.
3. DevTools boots, connects through our ws proxy to the app's own VM service,
   and calls the server API below.

---

## 4. The DevTools server contract (reverse-engineered)

**This is the most valuable part of this doc.** Sources: `devtools_shared`
(`lib/src/devtools_api.dart`, `lib/src/extensions/extension_model.dart`,
`lib/src/server/handlers/_devtools_extensions.dart`) and grepping the bundled
`main.dart.js`.

On desktop, extensions are found by the **DevTools server** reading
`.dart_tool/package_config.json` and serving each package's prebuilt
`extension/devtools/build/`. A device has neither. So `bundle` does that
discovery at build time and the app's server replays the result.

### Endpoints DevTools calls (all observed live)
| Path | We return | Notes |
|---|---|---|
| `/api/ping` | `200 OK` | **This is what makes DevTools believe a server exists.** Without it, no server-backed features and no extension discovery. Not present in `devtools_shared`'s `ServerApi` — found by grepping the frontend. |
| `/api/serveAvailableExtensions?packageRootUri=…` | `{"extensions":[…],"logs":[]}` | **`packageRootUri` arrives EMPTY on device** (`?packageRootUri` with no value) — DevTools can't resolve a package root there. We ignore the param entirely. |
| `/api/extensionEnabledState?…&name=<ext>` | `"enabled"` | Called per extension **only for ones it successfully parsed** — a useful signal that parsing worked. |
| `/api/getPreferenceValue?key=…` | `true` for `experiment.wasmOptOut`, else `null` | ~19 of these fire at boot. |
| `/api/*` (anything else) | `200 null` | Benign catch-all so init doesn't error. |
| `*/flutter_service_worker.js` | self-unregistering SW | Kills stale caches (a cached wasm build otherwise pins a blank page forever). |

### Per-extension JSON (must match `DevToolsExtensionConfig.parse`)
```json
{
  "name": "provider",                    // must match ^[a-z0-9_]*$ or parse throws
  "issueTracker": "https://…",
  "version": "0.0.1",
  "materialIconCodePoint": 57521,        // int or String
  "requiresConnection": "true",
  "extensionAssetsPath": "assets/devtools_extensions/provider_0.0.1",
  "devtoolsOptionsUri": "file:///devtools_options.yaml",
  "isPubliclyHosted": "false",           // String, bool.parse'd
  "detectedFromStaticContext": "false"   // String, bool.parse'd
}
```
Missing/mistyped keys → `parse` throws → the extension is silently dropped.

### The iframe URL rule
The frontend builds it as
`<base>/devtools_extensions/<name.toLowerCase()>_<version>/index.html?theme=…`
— derived from **name + version**, not from `extensionAssetsPath`.

> ⚠️ **`version` is the EXTENSION's version from its `config.yaml`, NOT the
> package version.** `provider 6.1.5` ships extension `0.0.1` →
> `provider_0.0.1`. Getting this wrong = broken iframe path.

### Serving the iframe
- `index.html` — must rewrite `<base href="/">` → `<base href="/devtools_extensions/<id>/">`,
  or its relative assets resolve at the server root and load *DevTools'* bootstrap.
- `canvaskit/*` — served from the shared `assets/devtools/canvaskit/` (identical
  engine revision). Each extension ships its own ~37 MB copy; we skip them all
  and share one. Only ~7 MB per extension is bundled.

---

## 5. Verified on device (how to reproduce)

Emulator, Android, profile build, clean app consuming the package by path:

```sh
flutter create --platforms=android demo && cd demo
# pubspec: embedded_devtools (path:), provider, shared_preferences
flutter pub get
dart run embedded_devtools:init
# main.dart: EmbeddedDevTools.start(logRequests: true) + EmbeddedDevToolsOverlay
flutter build apk --profile
adb install -r build/app/outputs/flutter-apk/app-profile.apk
```

`start(logRequests: true)` logs every non-asset request — **this is the main
debugging tool**; it's how the manifest bug was found. Read it with:

```sh
adb logcat -d | grep -oE "\[embedded_devtools\] .*"
```

---

## 6. RESOLVED (not fixable): extensions can't eval

**Root cause: expression evaluation requires a compilation service that only
exists when a computer runs `flutter run`.** Proven by driving the VM service
through our own proxy on a **debug** iOS build:

```
evaluate(rootLib, '1+1')
→ {"code":113,"message":"Expression compilation error",
   "data":{"details":"_compileExpression: No compilation service available;
                      cannot evaluate from source."}}
```

The Dart VM does not compile Dart source. `evaluate` delegates to
`_compileExpression`, a service registered by the **`frontend_server` process
that `flutter_tools` spawns**. A standalone app has no Flutter tool attached →
no compilation service → **eval is impossible, in debug too**.

`provider`'s extension calls `evaluate`/`getObject`/`getIsolate`. So do
`riverpod`, `shared_preferences` (it evals
`SharedPreferencesDevToolsExtensionData().…`) and `get_it`. Hence all four
render and then fail. provider's *"...use version >=5.0.0"* message is a red
herring.

**This is unfixable here.** A compilation service would mean shipping the Dart
SDK, platform dill, and package sources to the device, and running a JIT VM to
host them. Not feasible, and impossible in AOT builds regardless.

### Hypotheses that were wrong (don't retry)
1. **`kDebugMode` gating.** provider guards its hooks with `kDebugMode`, which
   is false in profile — plausible, and **disproved**: a debug build failed
   identically.
2. **DevTools misdetecting "profile build" through our proxy.** DevTools does
   label a debug build `(profile build)` in our setup, which looked causal. But
   the proxy is exonerated: `getIsolate` through it returns **71 extensionRPCs
   including `ext.flutter.debugAllowBanner`**, and the eval failure is the VM's
   own, upstream of anything DevTools decides. The mislabel is cosmetic and
   unrelated. (It also isn't computed from `debugAllowBanner` in this DevTools
   version — that string appears once, only in a descriptor list.)

### What still works
The proxy is a raw byte pipe with no filtering, so an extension that used
**registered service extensions** (`ext.<name>.*`) instead of eval would work.
We know of no popular one that does. DevTools' own eval surfaces (evaluation
console, watch expressions) are unavailable for the same reason. Inspector,
Performance, CPU, Memory, Network and Logging need no eval and are unaffected.

---

## 7. Open issue: 94 MB of assets ship to production

Measured with `flutter build apk --release --target-platform=android-arm64 --analyze-size`
on a demo whose `main.dart` guards **both** call sites (with `!kReleaseMode` —
see the warning below):

- ✅ `embedded_devtools` **Dart code**: tree-shaken completely — zero bytes in the
  release binary. `kDebugMode` is a const `false`, so AOT drops the branches.
- ❌ `assets/flutter_assets/assets/devtools/`: **490 files, 94.4 MB still in the
  release APK** (44 MB compressed).

**Assets are never tree-shaken.** Anything under `flutter: assets:` is bundled
unconditionally; there's no reachability analysis for assets. Code guards buy a
few hundred KB and none of the 94 MB.

> ⚠️ **Guard with `!kReleaseMode`, never `kDebugMode`.** The SDK defines
> `const bool kDebugMode = !kReleaseMode && !kProfileMode;`
> (`flutter/lib/src/foundation/constants.dart:64`) — so `kDebugMode` is **false
> in profile**, and `if (kDebugMode) EmbeddedDevTools.start()` silently disables
> the tool in the exact build QA gets. Both are compile-time consts, so
> `!kReleaseMode` tree-shakes just as well in release. Guards are optional
> anyway: `start()` already no-ops in release.

**Candidate fix (untested): asset flavors.**
```yaml
flutter:
  assets:
    - path: assets/devtools/
      flavors: [qa]
```
Then `--flavor qa` bundles them and `--flavor prod` doesn't. If this works on
3.44, `bundle` should emit flavored entries (probably opt-in via a
`--flavor` arg) so exclusion is automatic rather than README advice.

---

## 8. Constraints that are physics, not bugs

- **Release has no VM service.** The AOT product engine compiles it out, so
  DevTools cannot attach. `start()` no-ops and the overlay renders nothing in
  release. Use `--profile`. This also rules out iOS TestFlight (release only).
- **The wasm DevTools build cannot be used.** skwasm needs `SharedArrayBuffer`
  via cross-origin isolation, which a plain-http loopback server can't grant →
  blank page. We force dart2js+canvaskit via `compiler=js` **and** by answering
  `experiment.wasmOptOut` → `true`. Don't "simplify" either one away.
- **Android blocks cleartext to loopback** (API 28+) → `ERR_CLEARTEXT_NOT_PERMITTED`
  in the WebView. `init` writes a loopback-scoped `network_security_config.xml`
  and references it from the **debug and profile manifests only** — never
  `src/main`, so it can't reach release.
- **Android 12+ freezes backgrounded apps**, killing the server while the phone's
  browser is foregrounded. `KeepAliveService` mitigates. The in-app WebView
  sidesteps it entirely.

---

## 9. Gotchas that already cost time

1. **Assets must be *declared*, not just present.** `manifest.json` existed on
   disk but its directory was never in the pubspec, so `rootBundle` couldn't
   read it → empty extension list → *"No extensions available"*. `_copyTree`
   only records dirs it **copies into**; the manifest is written afterward, so
   `dirs.add(extensionsDest)` is load-bearing. This looked like "the whole
   approach doesn't work" and was one line.
2. **Extension version ≠ package version.** See §4.
3. **Debug does NOT permit cleartext.** Flutter's debug manifest template does
   *not* set `usesCleartextTraffic`, and the Gradle plugin doesn't inject it.
   Debug needs the network security config just like profile.
4. **`print`/`debugPrint` do reach logcat in profile** (tag `flutter`), but
   nothing appears if the code never runs — don't conclude "logging is broken."
5. **`adb shell input tap` is eaten during app startup.** The 118 MB APK cold-starts
   slowly (400+ skipped frames). Poll until the UI is actually up before tapping,
   or you'll "prove" something failed when the tap never landed.
6. **`adb shell screencap` prints a multi-display warning to stdout**, corrupting
   `exec-out > file.png`. Write to `/sdcard` and `adb pull` instead. `-d 0` is
   not reliably valid.
7. **`evaluate` never works here** — no compilation service without
   `flutter run` (§6). If something "can't connect to the app", check whether it
   evals before theorising about build modes or the proxy. One `evaluate` call
   through the proxy answers in seconds what two wrong hypotheses could not.
8. **Don't trust reasoning over execution here.** Three confident hypotheses
   (debug allows cleartext; `kDebugMode` gating explains §6; the proxy hides
   service extensions) were all wrong, and each was killed in minutes by
   actually running the thing.

---

## 10. Next steps

1. ~~**§6** — root-cause the extension↔package connection.~~ **Done: it's
   unfixable** (eval needs a compilation service that only `flutter run`
   provides). No code change possible; documented instead. This no longer
   blocks a pub.dev release — the limitation just has to be stated honestly.
2. **§7** — test asset flavors; if they work, teach `bundle` to emit them.
   (Lower priority: the owner has said he doesn't mind the size.)
3. Consider `hook/build.dart` + data assets to replace the `bundle` CLI once
   `dartDataAssets` reaches stable (it's **master-only** in 3.44 —
   `flutter_tools/lib/src/features.dart`). That would remove the manual command
   with no API change for users. Flutter's own l10n codegen can't be imitated:
   `GenerateLocalizationsTarget()` is hardcoded into flutter_tools' build
   pipeline and is not an extension point, and pub deliberately has no
   post-`pub get` hook.
4. Only then: publish to pub.dev.
