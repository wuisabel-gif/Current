import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:current/main.dart';

void main() {
  testWidgets('Current renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CurrentApp());
    await tester.pump();

    expect(find.byType(CurrentScreen), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    expect(find.text('Density'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
  });
}
