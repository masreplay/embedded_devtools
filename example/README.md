# embedded_devtools_example

Minimal app showing `embedded_devtools`: one `start()` call and one overlay.

The DevTools assets (~90 MB) are generated, not committed — so run `init` once
before building:

```sh
flutter pub get
dart run embedded_devtools:init     # bundles DevTools + extensions, wires up Android
flutter build apk --profile
adb install -r build/app/outputs/flutter-apk/app-profile.apk
```

Launch the app and tap the bubble.

**Use `--profile`** (or `--debug`). Release builds have no Dart VM service, so
DevTools has nothing to attach to and the overlay renders nothing.

`shared_preferences` is included as a dependency only to demonstrate extension
discovery — `init` finds its DevTools extension and bundles it automatically,
with no code here referencing it.
