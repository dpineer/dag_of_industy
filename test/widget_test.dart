// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dag_of_industy/main.dart';

void main() {
  testWidgets('Industrial Simulator App Test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: IndustrialSimulatorApp()));

    // Verify that the app starts correctly
    expect(find.text('生产网络 DAG 规划区'), findsOneWidget);
    expect(find.byIcon(Icons.add_box), findsOneWidget);
    expect(find.byIcon(Icons.analytics), findsOneWidget);
  });
}
