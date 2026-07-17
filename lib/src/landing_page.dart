/// The `/qa` landing page. DevTools always connects through this server's
/// websocket proxy (`ws://<this host>:<this port><vm ws path>`), which works
/// identically from the device's own browser and from a PC on the LAN — the
/// VM service itself only listens on the device's loopback interface.
String landingPageHtml({required int vmPort, required String vmWsPath}) => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Embedded DevTools</title>
<style>
body{font-family:system-ui;margin:2rem;background:#111;color:#eee}
a.btn{display:inline-block;padding:1rem 2rem;background:#2196f3;color:#fff;
border-radius:8px;text-decoration:none;font-size:1.2rem}
code{background:#222;padding:2px 6px;border-radius:4px;word-break:break-all}
</style>
</head>
<body>
<h1>Flutter DevTools</h1>
<p>VM service (device-local port $vmPort), proxied at:
<code id="ws"></code></p>
<p><a id="open" class="btn" href="#">Open DevTools</a></p>
<script>
var wsPath = '$vmWsPath';
var ws = 'ws://' + location.host + wsPath;
document.getElementById('ws').textContent = ws;
// compiler=js forces the dart2js+canvaskit DevTools build; the wasm build
// needs cross-origin isolation this server can't grant, and renders blank.
document.getElementById('open').href =
    '/?ide=EmbeddedDevTools&uri=' + encodeURIComponent(ws) + '&compiler=js';
</script>
</body>
</html>
''';

String landingPageNoVmHtml() => '''
<!DOCTYPE html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Embedded DevTools</title></head>
<body>
<h1>Flutter DevTools</h1>
<p>No Dart VM service found. This build was compiled in release mode (or the
VM service is disabled), so DevTools is unavailable — the AOT product engine
compiles the VM service out. Use a <code>--profile</code> build instead.</p>
</body>
</html>
''';
