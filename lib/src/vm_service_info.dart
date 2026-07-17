import 'dart:developer' as developer;

/// The app's own Dart VM service endpoint, discovered at runtime.
class VmServiceInfo {
  VmServiceInfo(this.httpUri);

  /// e.g. `http://127.0.0.1:43333/NRPLsCVx3rw=/`
  final Uri httpUri;

  int get port => httpUri.port;

  /// Path-only websocket suffix, e.g. `/NRPLsCVx3rw=/ws`.
  String get wsPath {
    final p = httpUri.path.endsWith('/') ? httpUri.path : '${httpUri.path}/';
    return '${p}ws';
  }

  /// Returns null when no VM service is available (release builds, or
  /// `--disable-vm-service`).
  static Future<VmServiceInfo?> discover() async {
    final info = await developer.Service.getInfo();
    final uri = info.serverUri;
    if (uri == null) return null;
    return VmServiceInfo(uri);
  }
}
