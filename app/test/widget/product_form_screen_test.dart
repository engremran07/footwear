import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/screens/product_form_screen.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/widgets/error_state.dart';

void main() {
  testWidgets('product form shows retry when profile loading fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) =>
                Stream<UserModel?>.error(StateError('profile unavailable')),
          ),
        ],
        child: const MaterialApp(home: ProductFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
