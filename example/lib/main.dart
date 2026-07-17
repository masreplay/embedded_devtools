import 'package:embedded_devtools/embedded_devtools.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Serves DevTools from this app's assets and proxies its own VM service.
  // A no-op in release builds, which have no VM service.
  EmbeddedDevTools.start();

  runApp(MaterialApp(
    home: const HomePage(),
    // The draggable bubble that opens DevTools inside the app.
    builder: (context, child) =>
        EmbeddedDevToolsOverlay(child: child ?? const SizedBox()),
  ));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('embedded_devtools')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Tap the bubble to open DevTools.'),
            const SizedBox(height: 8),
            Text('$_count', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _count++),
        child: const Icon(Icons.add),
      ),
    );
  }
}
