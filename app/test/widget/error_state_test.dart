import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/widgets/error_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ErrorState rendering', () {
    testWidgets('displays error message', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(message: 'Something went wrong')),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('shows error icon', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(message: 'Error!')),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('does not show retry button by default', (tester) async {
      await tester.pumpWidget(
        _wrap(const ErrorState(message: 'Error!')),
      );
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('shows retry button when callback provided', (tester) async {
      await tester.pumpWidget(
        _wrap(ErrorState(message: 'Error!', onRetry: () {})),
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('retry button callback fires', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        _wrap(ErrorState(
          message: 'Error!',
          onRetry: () => retried = true,
        )),
      );
      await tester.tap(find.byType(OutlinedButton));
      expect(retried, isTrue);
    });
  });
}
