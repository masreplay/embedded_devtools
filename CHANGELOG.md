## 0.1.0

- Initial release.
- Embedded HTTP server serving the Flutter DevTools web build from app assets.
- Websocket proxy to the app's own VM service.
- `EmbeddedDevToolsOverlay` — draggable bubble opening full DevTools in an
  in-app WebView, plus device/LAN links.
- DevTools extension discovery: extensions your dependencies ship appear in
  DevTools' own Extensions area, served from app assets.
- `bundle` CLI: copies the DevTools build from your Flutter SDK, discovers and
  copies extension builds, writes the runtime manifest, and updates pubspec.

- `init` CLI: one-command setup (Android wiring + assets + pubspec).
