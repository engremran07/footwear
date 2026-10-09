import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/screens/bootstrap_profile_screen.dart';
import 'package:footwear_erp/widgets/error_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'profile read errors show retry instead of missing-profile copy',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var profileReads = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            authUserProvider.overrideWith((ref) {
              profileReads++;
              return Stream.error(StateError('profile unavailable'));
            }),
          ],
          child: const MaterialApp(home: BootstrapProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('No workspace profile is assigned to this account.'),
        findsNothing,
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(profileReads, greaterThan(1));
      expect(tester.takeException(), isNull);
    },
  );
}
