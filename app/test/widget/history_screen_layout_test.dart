import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/models/transaction_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/history_provider.dart';
import 'package:footwear_erp/providers/route_provider.dart';
import 'package:footwear_erp/screens/history_screen.dart';

void main() {
  for (final locale in [AppLocale.en, AppLocale.ar, AppLocale.ur]) {
    testWidgets(
      'history invoice badge stays on the physical right in ${locale.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(420, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final now = Timestamp.now();
        final user = UserModel(
          id: 'seller-1',
          email: 'seller@example.com',
          displayName: 'Seller',
          role: UserRole.seller,
          assignedRouteIds: const ['route-1'],
          active: true,
          createdAt: now,
          updatedAt: now,
        );
        final transaction = TransactionModel(
          id: 'transaction-1',
          shopId: 'shop-1',
          shopName: 'A shop name long enough to be truncated in this row',
          routeId: 'route-1',
          type: TransactionModel.typeCashOut,
          amount: 125,
          invoiceId: 'invoice-1',
          invoiceNumber: 'INV-1001',
          createdBy: 'seller-1',
          createdAt: now,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appLocaleProvider.overrideWith(() => _FixedLocale(locale)),
              authUserProvider.overrideWith((ref) => Stream.value(user)),
              recentTransactionsProvider.overrideWith(
                (ref) => Stream.value([transaction]),
              ),
              routeCurrencyProvider('route-1').overrideWithValue('SAR'),
            ],
            child: MaterialApp(
              locale: locale.locale,
              home: const HistoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final shopRect = tester.getRect(find.text(transaction.shopName).first);
        final badgeRect = tester.getRect(find.text('INV-1001'));

        expect(badgeRect.center.dx, greaterThan(shopRect.center.dx));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _FixedLocale extends AppLocaleNotifier {
  _FixedLocale(this.locale);

  final AppLocale locale;

  @override
  AppLocale build() => locale;
}
