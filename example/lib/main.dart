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
