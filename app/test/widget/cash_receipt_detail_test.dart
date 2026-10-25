import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/invoice_model.dart';
import 'package:footwear_erp/models/user_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/invoice_provider.dart';
import 'package:footwear_erp/screens/invoice_detail_screen.dart';

void main() {
  testWidgets('cash receipt detail shows full payment and balance context', (
    tester,
  ) async {
    final now = Timestamp.fromDate(DateTime(2026, 10, 25, 9, 30));
    final receipt = InvoiceModel(
      id: 'receipt-1',
      invoiceNumber: 'REC-2026-0012',
      type: InvoiceModel.typeCashReceipt,
      shopId: 'shop-1',
      shopName: 'North Star Footwear',
      subtotal: 0,
      total: 250,
      amountReceived: 250,
      outstandingAmount: 0,
      status: InvoiceModel.statusPaid,
      paymentMethod: 'bank_transfer',
      paymentReference: 'BANK-7788',
      shopBalanceBefore: 800,
      shopBalanceAfter: 550,
      cashReceiptSequence: 12,
      linkedInvoiceId: 'INV-2026-0040',
      sellerName: 'Ayesha Khan',
      createdBy: 'seller-1',
      createdAt: now,
      updatedAt: now,
    );
    final user = UserModel(
      id: 'seller-1',
      email: 'seller@example.com',
      displayName: 'Ayesha Khan',
      role: UserRole.seller,
      tenantId: 'workspace-1',
      active: true,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(user)),
          invoiceByIdProvider.overrideWith(
            (ref, invoiceId) => Stream.value(receipt),
          ),
        ],
        child: const MaterialApp(
          home: InvoiceDetailScreen(invoiceId: 'receipt-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REC-2026-0012'), findsOneWidget);
    expect(find.text('North Star Footwear'), findsOneWidget);
    expect(find.text('Received By'), findsOneWidget);
    expect(find.text('Ayesha Khan'), findsOneWidget);
    expect(find.text('Bank Transfer'), findsOneWidget);
    expect(find.text('BANK-7788'), findsOneWidget);
    expect(find.text('Account Balance Movement'), findsOneWidget);
    expect(find.textContaining('800.00'), findsOneWidget);
    expect(find.textContaining('550.00'), findsOneWidget);
    expect(
      find.byKey(const Key('cash_receipt_balance_summary')),
      findsOneWidget,
    );
    expect(find.text('INV-2026-0040'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
