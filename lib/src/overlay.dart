import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'devtools_server.dart';

/// Wraps the app (via `MaterialApp`'s `builder`) with a draggable bubble.
/// Tapping it opens a bottom sheet holding the full DevTools suite in an in-app
/// WebView, pointed at the embedded server — no external browser, no cable, no
/// IDE. Drag the handle to resize it between detents, or down to dismiss.
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
      if (url != null) _ensureWebView(url);
    });
  }

  void _closeSheet() {
    setState(() => _open = false);
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
                controller: _controller,
                progress: _progress,
                sheetHeightFraction: _sheetHeightFraction,
                animDuration: _animDuration,
                onClose: _closeSheet,
                onReload: _reloadWebView,
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
                  // Flutter brand blue.
                  color: const Color(0xFF0175C2),
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: FlutterLogo(size: 22),
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
    required this.controller,
    required this.progress,
    required this.sheetHeightFraction,
    required this.animDuration,
    required this.onClose,
    required this.onReload,
  });

  final bool open;
  final WebViewController? controller;
  final int progress;
  final double sheetHeightFraction;
  final Duration animDuration;
  final VoidCallback onClose;
  final VoidCallback onReload;

  @override
  State<_DevToolsBottomSheet> createState() => _DevToolsBottomSheetState();
}

class _DevToolsBottomSheetState extends State<_DevToolsBottomSheet> {
  // Owned by Overlay after insert; rebuild via markNeedsBuild so the entry
  // always paints current widget fields (open / drag position / progress).
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

  /// Heights the sheet settles at, as fractions of the screen. The last must
  /// equal [_DevToolsBottomSheet.sheetHeightFraction] — the sheet is always
  /// laid out at that height and translated down to show less, so the content
  /// (and the WebView) never relayouts while dragging.
  static const _snaps = <double>[0.3, 0.6, 0.9];

  /// Velocity beyond which a flick jumps a detent instead of snapping to the
  /// nearest one.
  static const _flingVelocity = 700.0;

  /// The detent the sheet rests at while open.
  double _snap = _snaps.last;

  /// Live height fraction while a finger is down; null when not dragging.
  double? _dragFraction;

  bool get _dragging => _dragFraction != null;

  void _onDragStart(DragStartDetails _) => setState(() => _dragFraction = _snap);

  void _onDragUpdate(DragUpdateDetails d, double screenHeight) {
    setState(() {
      // Dragging down (positive dy) shows less of the sheet.
      _dragFraction = ((_dragFraction ?? _snap) - d.delta.dy / screenHeight)
          .clamp(0.0, widget.sheetHeightFraction);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.velocity.pixelsPerSecond.dy;
    final pos = _dragFraction ?? _snap;

    // null target => dismiss.
    double? target;
    if (velocity > _flingVelocity) {
      // Flick down: drop to the next detent below, or dismiss past the last.
      final below = _snaps.where((s) => s < pos - 0.02);
      target = below.isEmpty ? null : below.last;
    } else if (velocity < -_flingVelocity) {
      // Flick up: rise to the next detent above.
      final above = _snaps.where((s) => s > pos + 0.02);
      target = above.isEmpty ? _snaps.last : above.first;
    } else if (pos < _snaps.first / 2) {
      // Released below half the smallest detent: treat as dismiss.
      target = null;
    } else {
      target = _snaps
          .reduce((a, b) => (a - pos).abs() <= (b - pos).abs() ? a : b);
    }

    setState(() {
      _dragFraction = null;
      if (target != null) _snap = target;
    });
    if (target == null) widget.onClose();
  }

  Widget _buildContent(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxFraction = widget.sheetHeightFraction;
    final sheetHeight = media.size.height * maxFraction;

    // How much of the sheet is on screen right now, as a fraction of screen.
    final visible = _dragFraction ?? _snap;
    // AnimatedSlide's offset is a fraction of the child's own height.
    final slide = (1 - visible / maxFraction).clamp(0.0, 1.0);

    return IgnorePointer(
      ignoring: !widget.open,
      child: Stack(
        children: [
          AnimatedOpacity(
            // Dim in proportion to how much sheet is showing, so a peek at the
            // smallest detent barely dims the app behind it.
            opacity: widget.open ? (visible / maxFraction).clamp(0.0, 1.0) : 0,
            duration: _dragging ? Duration.zero : widget.animDuration,
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
              // Open sheets sit at their detent; closed ones sit fully off
              // screen. While a finger is down the duration is zero so the
              // sheet tracks it 1:1 instead of lagging behind an animation.
              offset: Offset(0, widget.open ? slide : 1),
              duration: _dragging ? Duration.zero : widget.animDuration,
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
                      // Drag target: the handle and header only. The WebView
                      // below owns its own vertical gestures (DevTools scrolls),
                      // so dragging there must not move the sheet.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: _onDragStart,
                        onVerticalDragUpdate: (d) =>
                            _onDragUpdate(d, media.size.height),
                        onVerticalDragEnd: _onDragEnd,
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
                              canReload: widget.controller != null,
                              onClose: widget.onClose,
                              onReload: widget.onReload,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        // Keep the WebView clear of the system navigation bar:
                        // the sheet is bottom-aligned and full-bleed, so without
                        // this its last strip sits under the gesture bar and
                        // taps there never reach DevTools.
                        child: Padding(
                          padding: EdgeInsets.only(bottom: media.padding.bottom),
                          // Keep the WebView mounted whenever it exists so
                          // closing the sheet does not dispose it.
                          child: widget.controller != null
                              ? TickerMode(
                                  enabled: widget.open,
                                  child: _PersistentWebView(
                                    controller: widget.controller!,
                                    progress: widget.progress,
                                  ),
                                )
                              : const _NoServer(),
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
    required this.canReload,
    required this.onClose,
    required this.onReload,
  });

  final bool canReload;
  final VoidCallback onClose;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'DevTools',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
          const Spacer(),
          if (canReload)
            IconButton(
              tooltip: 'Reload DevTools',
              onPressed: onReload,
              icon: const Icon(Icons.refresh, color: Colors.white),
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
