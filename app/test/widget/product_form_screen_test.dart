import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/screens/product_form_screen.dart';
import 'package:footwear_erp/models/user_model.dart';

void main() {
  testWidgets('profile stream failure is mapped during product save', (
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

    await tester.enterText(find.byType(TextFormField), 'Canvas Shoe');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
