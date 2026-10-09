import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/screens/settings_screen.dart';
import 'package:footwear_erp/widgets/error_state.dart';

void main() {
  testWidgets('settings shows retry instead of default business controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.error(StateError('profile unavailable')),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Company Name'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}