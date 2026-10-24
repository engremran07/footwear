import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/error_state.dart';

void main() {
  testWidgets('ErrorState disables shake motion when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ErrorState(message: 'Could not load')),
        ),
      ),
    );

    expect(find.byType(Animate), findsNothing);
  });
}
