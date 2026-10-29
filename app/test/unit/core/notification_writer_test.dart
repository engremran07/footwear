import 'package:flutter_test/flutter_test.dart';

import 'package:footwear_erp/core/utils/notification_writer.dart';

void main() {
  test('seller notification IDs are stable and source-scoped', () {
    expect(
      sellerNotificationDocumentId(
        sourceType: 'transaction',
        sourceId: 'tx-123',
      ),
      'transaction_tx-123',
    );
    expect(
      sellerNotificationDocumentId(
        sourceType: 'invoice',
        sourceId: 'invoice-123',
      ),
      'invoice_invoice-123',
    );
  });

  test('seller notifications retain the linked source and tenant fields', () {
    final notification = buildSellerNotification(
      sourceType: 'invoice',
      sourceId: 'invoice-123',
      sellerId: 'seller-1',
      sellerName: 'Seller One',
      tenantId: 'tenant-1',
      shopId: 'shop-1',
      shopName: 'Shop One',
      routeId: 'route-1',
      amount: 125,
      transactionType: 'cash_out',
      invoiceNumber: 'INV-2026-0001',
    );

    expect(notification, containsPair('type', 'invoice'));
    expect(notification, containsPair('ref_id', 'invoice-123'));
    expect(notification, containsPair('created_by', 'seller-1'));
    expect(notification, containsPair('seller_id', 'seller-1'));
    expect(notification, containsPair('tenant_id', 'tenant-1'));
    expect(notification, containsPair('shop_id', 'shop-1'));
    expect(notification, containsPair('route_id', 'route-1'));
    expect(notification, containsPair('amount', 125));
    expect(notification, containsPair('invoice_number', 'INV-2026-0001'));
    expect(notification['created_at'], isNotNull);
  });

  test('cash-receipt invoices can create linked cash-in notifications', () {
    final notification = buildSellerNotification(
      sourceType: 'invoice',
      sourceId: 'receipt-123',
      sellerId: 'seller-1',
      sellerName: 'Seller One',
      tenantId: 'tenant-1',
      shopId: 'shop-1',
      shopName: 'Shop One',
      routeId: 'route-1',
      amount: 125,
      transactionType: 'cash_in',
      invoiceNumber: 'REC-2026-0001',
    );

    expect(notification, containsPair('type', 'invoice'));
    expect(notification, containsPair('transaction_type', 'cash_in'));
    expect(notification, containsPair('invoice_number', 'REC-2026-0001'));
  });

  test('invoice notifications reject credit-note returns', () {
    expect(
      () => buildSellerNotification(
        sourceType: 'invoice',
        sourceId: 'credit-note-1',
        sellerId: 'seller-1',
        sellerName: 'Seller One',
        tenantId: 'tenant-1',
        shopId: 'shop-1',
        shopName: 'Shop One',
        routeId: 'route-1',
        amount: 125,
        transactionType: 'return',
        invoiceNumber: 'CN-2026-0001',
      ),
      throwsArgumentError,
    );
  });

  test('seller notification builders reject invalid source data', () {
    expect(
      () => sellerNotificationDocumentId(
        sourceType: 'unknown',
        sourceId: 'source-1',
      ),
      throwsArgumentError,
    );
    expect(
      () => sellerNotificationDocumentId(
        sourceType: 'transaction',
        sourceId: 'nested/source',
      ),
      throwsArgumentError,
    );
    expect(
      () => buildSellerNotification(
        sourceType: 'transaction',
        sourceId: 'tx-1',
        sellerId: 'seller-1',
        sellerName: 'Seller One',
        tenantId: 'tenant-1',
        shopId: 'shop-1',
        shopName: 'Shop One',
        routeId: 'route-1',
        amount: 0,
        transactionType: 'cash_in',
      ),
      throwsArgumentError,
    );
  });
}
