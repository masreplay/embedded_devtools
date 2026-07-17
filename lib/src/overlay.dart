import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'devtools_server.dart';

/// Wraps the app (via `MaterialApp`'s `builder`) with a draggable bubble.
/// Tapping it opens a full-screen sheet with two tabs:
///
/// - **DevTools** — the full DevTools suite in an in-app WebView, pointed at
///   the embedded server. No external browser, no cable, no IDE.
/// - **Links** — the same URLs for opening DevTools in the phone's browser or
///   from a PC on the same network.
///
/// Visible in debug and profile builds. Release builds render nothing: the
/// AOT product engine has no VM service, so DevTools has nothing to attach to.
class EmbeddedDevToolsOverlay extends StatefulWidget {
  const EmbeddedDevToolsOverlay({
    super.key,
    required this.child,
    this.server,
  });

  final Widget child;

  /// Overrides [EmbeddedDevTools.server]; for tests.
  final DevToolsServerHandle? server;

  @override
  State<EmbeddedDevToolsOverlay> createState() =>
      _EmbeddedDevToolsOverlayState();
}

class _EmbeddedDevToolsOverlayState extends State<EmbeddedDevToolsOverlay> {
  bool _open = false;
  Offset _bubble = const Offset(16, 200);

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode && widget.server == null) return widget.child;
    if (widget.server != null) return _build(context, widget.server);
    return ValueListenableBuilder<DevToolsServer?>(
      valueListenable: EmbeddedDevTools.serverNotifier,
      builder: (context, server, _) => _build(context, server),
    );
  }

  Widget _build(BuildContext context, DevToolsServerHandle? server) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (_open)
            Positioned.fill(
              child: _DevToolsSheet(
                server: server,
                onClose: () => setState(() => _open = false),
              ),
            ),
          if (!_open)
            Positioned(
              left: _bubble.dx,
              top: _bubble.dy,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _bubble += d.delta),
                onTap: () => setState(() => _open = true),
                child: Material(
                  color: Colors.blueGrey.shade800,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.build, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DevToolsSheet extends StatelessWidget {
  const _DevToolsSheet({required this.server, required this.onClose});

  final DevToolsServerHandle? server;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      // Tooltips and dialogs need an Overlay ancestor; inside MaterialApp's
      // builder there is none, so provide our own.
      child: Overlay(initialEntries: [OverlayEntry(builder: _buildContent)]),
    );
  }

  Widget _buildContent(BuildContext context) {
    final devToolsUrl = server?.devToolsUrl;
    return DefaultTabController(
      length: 2,
      child: Material(
        // Fully opaque: anything less lets the host app's UI (e.g. its AppBar
        // title) bleed through and collide with the sheet's own chrome.
        color: const Color(0xFF111111),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'DevTools',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const TabBar(
                tabs: [Tab(text: 'DevTools'), Tab(text: 'Links')],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    if (devToolsUrl != null)
                      _WebViewTab(url: devToolsUrl)
                    else
                      const _NoServer(),
                    _LinksTab(server: server),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoServer extends StatelessWidget {
  const _NoServer();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No DevTools server is running.\n\n'
          'Release builds have no Dart VM service, so DevTools cannot attach. '
          'Build with --profile (release-grade performance, VM service '
          'intact) and call EmbeddedDevTools.start() at app startup.',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

/// Renders the full DevTools web build inside the app's own WebView.
class _WebViewTab extends StatefulWidget {
  const _WebViewTab({required this.url});

  final Uri url;

  @override
  State<_WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends State<_WebViewTab> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF111111))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
      ],
    );
  }
}

class _LinksTab extends StatelessWidget {
  const _LinksTab({required this.server});

  final DevToolsServerHandle? server;

  @override
  Widget build(BuildContext context) {
    final server = this.server;
    if (server == null) return const _NoServer();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Open DevTools in this phone\'s browser, or from a PC on the same '
            'WiFi:',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Uri>>(
            future: server.lanUrls(),
            builder: (context, snapshot) {
              final urls = [server.localUrl, ...?snapshot.data];
              return ListView(
                children: [for (final url in urls) _UrlRow(url: url)],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: SelectableText(
        '$url',
        style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 16),
      ),
      subtitle: Text(
        url.host == '127.0.0.1'
            ? 'This device (open in the phone browser)'
            : 'LAN — open from a PC on the same network',
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white70),
            onPressed: () => Clipboard.setData(ClipboardData(text: '$url')),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser, color: Colors.white70),
            onPressed: () =>
                launchUrl(url, mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    );
  }
}
