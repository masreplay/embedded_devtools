import 'package:embedded_devtools/embedded_devtools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeServer implements DevToolsServerHandle {
  @override
  int get port => 9200;

  @override
  Uri get localUrl => Uri.parse('http://127.0.0.1:9200/qa');

  // Null keeps the WebView out of widget tests (the webview platform has no
  // test implementation); the Links tab still renders.
  @override
  Uri? get devToolsUrl => null;

  @override
  List<DevToolsExtensionInfo> get extensions => const [];

  @override
  Future<List<Uri>> lanUrls() async => [Uri.parse('http://10.0.0.5:9200/qa')];
}

void main() {
  testWidgets('bubble opens the sheet and lists the urls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmbeddedDevToolsOverlay(
          server: _FakeServer(),
          child: const Text('app'),
        ),
      ),
    );
    expect(find.text('app'), findsOneWidget);
    expect(find.byIcon(Icons.build), findsOneWidget);

    await tester.tap(find.byIcon(Icons.build));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Links'));
    await tester.pumpAndSettle();

    expect(find.textContaining('127.0.0.1:9200'), findsOneWidget);
    expect(find.textContaining('10.0.0.5:9200'), findsOneWidget);
  });

  testWidgets('sheet closes back to the bubble', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EmbeddedDevToolsOverlay(
          server: _FakeServer(),
          child: const Text('app'),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.build));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.build), findsOneWidget);
  });

  testWidgets('explains itself when no server is running', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: EmbeddedDevToolsOverlay(child: Text('app'))),
    );
    await tester.tap(find.byIcon(Icons.build));
    await tester.pumpAndSettle();
    expect(find.textContaining('No DevTools server is running'), findsWidgets);
  });
}
