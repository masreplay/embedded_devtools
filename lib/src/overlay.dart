import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'devtools_server.dart';

/// Wraps the app (via `MaterialApp`'s `builder`) with a draggable bubble.
/// Tapping it opens a bottom sheet with:
///
/// - **DevTools** — the full DevTools suite in an in-app WebView, pointed at
///   the embedded server. No external browser, no cable, no IDE.
/// - **Links** — the same URLs for opening DevTools in the phone's browser or
///   from a PC on the same network.
///
/// The WebView is kept alive after the sheet is dismissed so reopening does
/// not cold-boot DevTools. Use the refresh control to force a reload.
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
  static const _sheetHeightFraction = 0.9;
  static const _animDuration = Duration(milliseconds: 280);

  bool _open = false;
  bool _showLinks = false;
  /// True after the first open so the sheet (and WebView) stay in the tree.
  bool _sheetMounted = false;
  Offset _bubble = const Offset(16, 200);

  WebViewController? _controller;
  Uri? _loadedUrl;
  int _progress = 0;

  void _ensureWebView(Uri url) {
    if (_controller != null && _loadedUrl == url) return;
    _loadedUrl = url;
    _progress = 0;
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
      ..loadRequest(url);
  }

  void _openSheet(DevToolsServerHandle? server) {
    final url = server?.devToolsUrl;
    setState(() {
      _open = true;
      _sheetMounted = true;
      _showLinks = false;
      if (url != null) _ensureWebView(url);
    });
  }

  void _closeSheet() {
    setState(() {
      _open = false;
      _showLinks = false;
    });
  }

  void _reloadWebView() {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _progress = 0);
    controller.reload();
  }

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
          if (_sheetMounted)
            Positioned.fill(
              child: _DevToolsBottomSheet(
                open: _open,
                showLinks: _showLinks,
                server: server,
                controller: _controller,
                progress: _progress,
                sheetHeightFraction: _sheetHeightFraction,
                animDuration: _animDuration,
                onClose: _closeSheet,
                onReload: _reloadWebView,
                onShowLinks: () => setState(() => _showLinks = true),
                onShowDevTools: () => setState(() => _showLinks = false),
              ),
            ),
          if (!_open)
            Positioned(
              left: _bubble.dx,
              top: _bubble.dy,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _bubble += d.delta),
                onTap: () => _openSheet(server),
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

class _DevToolsBottomSheet extends StatefulWidget {
  const _DevToolsBottomSheet({
    required this.open,
    required this.showLinks,
    required this.server,
    required this.controller,
    required this.progress,
    required this.sheetHeightFraction,
    required this.animDuration,
    required this.onClose,
    required this.onReload,
    required this.onShowLinks,
    required this.onShowDevTools,
  });

  final bool open;
  final bool showLinks;
  final DevToolsServerHandle? server;
  final WebViewController? controller;
  final int progress;
  final double sheetHeightFraction;
  final Duration animDuration;
  final VoidCallback onClose;
  final VoidCallback onReload;
  final VoidCallback onShowLinks;
  final VoidCallback onShowDevTools;

  @override
  State<_DevToolsBottomSheet> createState() => _DevToolsBottomSheetState();
}

class _DevToolsBottomSheetState extends State<_DevToolsBottomSheet> {
  // Owned by Overlay after insert; rebuild via markNeedsBuild so the entry
  // always paints current widget fields (open / links / progress).
  late final OverlayEntry _entry = OverlayEntry(builder: _buildContent);

  @override
  void didUpdateWidget(covariant _DevToolsBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      // Tooltips and dialogs need an Overlay ancestor; inside MaterialApp's
      // builder there is none, so provide our own.
      child: Overlay(initialEntries: [_entry]),
    );
  }

  Widget _buildContent(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheetHeight = media.size.height * widget.sheetHeightFraction;

    return IgnorePointer(
      ignoring: !widget.open,
      child: Stack(
        children: [
          AnimatedOpacity(
            opacity: widget.open ? 1 : 0,
            duration: widget.animDuration,
            curve: Curves.easeOut,
            child: GestureDetector(
              onTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: const ColoredBox(color: Color(0x99000000)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: Offset(0, widget.open ? 0 : 1),
              duration: widget.animDuration,
              curve: Curves.easeOutCubic,
              child: Material(
                color: const Color(0xFF111111),
                elevation: 8,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: sheetHeight,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      _SheetHeader(
                        showLinks: widget.showLinks,
                        canReload:
                            widget.controller != null && !widget.showLinks,
                        onClose: widget.onClose,
                        onReload: widget.onReload,
                        onShowLinks: widget.onShowLinks,
                        onShowDevTools: widget.onShowDevTools,
                      ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Keep the WebView mounted whenever it exists so
                            // closing / switching to Links does not dispose it.
                            if (widget.controller != null)
                              Offstage(
                                offstage: widget.showLinks,
                                child: TickerMode(
                                  enabled: widget.open && !widget.showLinks,
                                  child: _PersistentWebView(
                                    controller: widget.controller!,
                                    progress: widget.progress,
                                  ),
                                ),
                              )
                            else if (!widget.showLinks)
                              const _NoServer(),
                            if (widget.showLinks)
                              _LinksTab(server: widget.server),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.showLinks,
    required this.canReload,
    required this.onClose,
    required this.onReload,
    required this.onShowLinks,
    required this.onShowDevTools,
  });

  final bool showLinks;
  final bool canReload;
  final VoidCallback onClose;
  final VoidCallback onReload;
  final VoidCallback onShowLinks;
  final VoidCallback onShowDevTools;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              showLinks ? 'Links' : 'DevTools',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
          const Spacer(),
          if (canReload)
            IconButton(
              tooltip: 'Reload DevTools',
              onPressed: onReload,
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          if (showLinks)
            TextButton(
              onPressed: onShowDevTools,
              child: const Text('DevTools'),
            )
          else
            TextButton(
              onPressed: onShowLinks,
              child: const Text('Links'),
            ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
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

class _PersistentWebView extends StatelessWidget {
  const _PersistentWebView({
    required this.controller,
    required this.progress,
  });

  final WebViewController controller;
  final int progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (progress < 100) LinearProgressIndicator(value: progress / 100),
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
