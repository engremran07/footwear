// Extended tests for InvoiceModel covering fields added in v3.x (TEST-023–026).
// Complements the existing invoice_model_test.dart.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/models/invoice_model.dart';

void main() {
  final ts = Timestamp.fromMillisecondsSinceEpoch(0);

  InvoiceModel base({
    String status = InvoiceModel.statusIssued,
    Map<String, int> deductions = const {},
  }) => InvoiceModel(
    id: 'inv-ext-1',
    invoiceNumber: 'INV-2026-0099',
    type: InvoiceModel.typeSale,
    shopId: 'c1',
    shopName: 'Test Customer',
    subtotal: 1000.0,
    total: 1000.0,
    status: status,
    sellerInventoryDeductions: deductions,
    createdBy: 'u1',
    createdAt: ts,
    updatedAt: ts,
  );

  group('sellerInventoryDeductions — round-trip (TEST-023)', () {
    test('non-empty deductions survive fromJson/toJson round-trip', () {
      final deductions = {'doc-A': 12, 'doc-B': 6};
      final original = base(deductions: deductions);
      final json = original.toJson()
        ..['status'] = original.status
        ..['created_at'] = original.createdAt
        ..['updated_at'] = original.updatedAt;
      final restored = InvoiceModel.fromJson(json, original.id);
      expect(restored.sellerInventoryDeductions, equals(deductions));
    });
  });

  group(
    'sellerInventoryDeductions — empty map excluded from toJson (TEST-024)',
    () {
      test('empty deductions map is not written to toJson output', () {
        final model = base(deductions: const {});
        final json = model.toJson();
        expect(json.containsKey('seller_inventory_deductions'), isFalse);
      });

      test('non-empty deductions map IS written to toJson output', () {
        final model = base(deductions: {'doc-A': 3});
        final json = model.toJson();
        expect(json.containsKey('seller_inventory_deductions'), isTrue);
        expect(
          (json['seller_inventory_deductions'] as Map)['doc-A'],
          equals(3),
        );
      });
    },
  );

  group('partial status flags — mutual exclusion (TEST-025)', () {
    test('partial status → isPartial=true, all others false', () {
      final m = base(status: InvoiceModel.statusPartial);
      expect(m.isPartial, isTrue);
      expect(m.isIssued, isFalse);
      expect(m.isPaid, isFalse);
      expect(m.isVoid, isFalse);
      expect(m.isDraft, isFalse);
    });

    test('partial status fromJson round-trip preserves status', () {
      final json = base(status: 'partial').toJson()
        ..['status'] = 'partial'
        ..['created_at'] = ts
        ..['updated_at'] = ts;
      final m = InvoiceModel.fromJson(json, 'inv-p');
      expect(m.isPartial, isTrue);
    });
  });

  group('void status flags — mutual exclusion (TEST-026)', () {
    test('void status → isVoid=true, all others false', () {
      final m = base(status: InvoiceModel.statusVoid);
      expect(m.isVoid, isTrue);
      expect(m.isPartial, isFalse);
      expect(m.isIssued, isFalse);
      expect(m.isPaid, isFalse);
      expect(m.isDraft, isFalse);
    });

    test('void status fromJson round-trip preserves status', () {
      final json = base(status: 'void').toJson()
        ..['status'] = 'void'
        ..['created_at'] = ts
        ..['updated_at'] = ts;
      final m = InvoiceModel.fromJson(json, 'inv-v');
      expect(m.isVoid, isTrue);
    });
  });

  group('invoice type helpers round-trip', () {
    test('isSale true for type=sale', () {
      expect(base().isSale, isTrue);
    });

    test('isReturn true for type=return', () {
      final m = InvoiceModel(
        id: 'r1',
        invoiceNumber: 'INV-2026-0100',
        type: InvoiceModel.typeReturn,
        shopId: 'c1',
        shopName: 'Test',
        subtotal: 500,
        total: 500,
        status: InvoiceModel.statusIssued,
        createdBy: 'u1',
        createdAt: ts,
        updatedAt: ts,
      );
      expect(m.isReturn, isTrue);
      expect(m.isSale, isFalse);
    });
  });
}
