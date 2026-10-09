import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/product_variant_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/product_provider.dart';
import 'package:footwear_erp/screens/profile_screen.dart';
import 'package:footwear_erp/screens/variant_form_screen.dart';

void main() {
  testWidgets('profile save maps an auth-profile stream failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.error(StateError('profile unavailable')),
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Updated name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('variant save maps an auth-profile stream failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.error(StateError('profile unavailable')),
          ),
          productVariantsProvider.overrideWith(
            (ref, productId) => Stream.value(const <ProductVariantModel>[]),
          ),
        ],
        child: const MaterialApp(
          home: VariantFormScreen(productId: 'product-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Large / Black');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
