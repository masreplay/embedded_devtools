import 'dart:convert';
import 'dart:io';

import 'package:embedded_devtools/embedded_devtools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Guard with !kReleaseMode, NOT kDebugMode: kDebugMode is false in profile
  // builds, and profile is the build you hand to QA (release-grade speed, VM
  // service intact). kReleaseMode is a compile-time const, so release still
  // tree-shakes all of this away.
  //
  // The guards are optional — start() no-ops and the overlay renders nothing in
  // release anyway. They just let the AOT compiler drop the code entirely.
  if (!kReleaseMode) EmbeddedDevTools.start();

  runApp(
    MaterialApp(
      home: const HomePage(),
      builder: (context, child) {
        if (!kReleaseMode) {
          return EmbeddedDevToolsOverlay(child: child ?? const SizedBox());
        }
        return child ?? const SizedBox();
      },
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _client = HttpClient();
  int _sent = 0;
  String _status = 'No request sent yet.';
  bool _loading = false;

  /// Fires a GET so the DevTools **Network** tab has traffic to show
  /// (`dart:io` requests are profiled by the VM automatically).
  Future<void> _sendRequest() async {
    setState(() {
      _loading = true;
      _status = 'Sending…';
    });
    final n = _sent + 1;
    final url =
        Uri.parse('https://jsonplaceholder.typicode.com/todos/${n % 200 + 1}');
    try {
      final req = await _client.getUrl(url);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final title = (jsonDecode(body) as Map)['title'] as String? ?? '';
      setState(() {
        _sent = n;
        _status = '${res.statusCode} · ${url.path}\n$title';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _client.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('embedded_devtools')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Tap the bubble to open DevTools,\n'
                  'then watch requests appear in the Network tab.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loading ? null : _sendRequest,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: const Text('Send API request'),
              ),
              const SizedBox(height: 24),
              Text('Requests sent: $_sent',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_status,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
