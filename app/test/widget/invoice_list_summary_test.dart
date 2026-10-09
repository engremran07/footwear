import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/invoice_model.dart';
import 'package:footwear_erp/providers/auth_provider.dart';
import 'package:footwear_erp/providers/invoice_provider.dart';
import 'package:footwear_erp/screens/invoices_list_screen.dart';

void main() {
  testWidgets('invoice summary excludes voids and counts partial payments', (
    tester,
  ) async {
    final invoices = [
      _invoice('paid', 100, 100, 0, InvoiceModel.statusPaid),
      _invoice('partial', 100, 40, 60, InvoiceModel.statusPartial),
      _invoice('void', 500, 0, 500, InvoiceModel.statusVoid),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(null)),
          roleAwareInvoicesProvider.overrideWith(
            (ref) => AsyncData(invoices),
          ),
        ],
        child: const MaterialApp(home: InvoicesListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('200'), findsOneWidget);
    expect(find.text('140'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

InvoiceModel _invoice(
  String id,
  double total,
  double received,
  double outstanding,
  String status,
) {
  final now = Timestamp.now();
  return InvoiceModel(
    id: id,
    invoiceNumber: 'INV-$id',
    type: InvoiceModel.typeSale,
    shopId: 'shop-1',
    shopName: 'Shop',
    subtotal: total,
    total: total,
    amountReceived: received,
    outstandingAmount: outstanding,
    status: status,
    createdBy: 'admin-1',
    createdAt: now,
    updatedAt: now,
  );
}