import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/collections.dart';

String sellerNotificationDocumentId({
  required String sourceType,
  required String sourceId,
}) {
  final normalizedType = sourceType.trim();
  final normalizedId = sourceId.trim();
  if (normalizedType != 'invoice' && normalizedType != 'transaction') {
    throw ArgumentError.value(sourceType, 'sourceType');
  }
  if (normalizedId.isEmpty || normalizedId.contains('/')) {
    throw ArgumentError.value(sourceId, 'sourceId');
  }
  return '${normalizedType}_$normalizedId';
}

bool isActiveStandaloneTransactionNotificationSource(
  Map<String, dynamic> transaction,
) {
  final type = transaction['type'];
  final createdBy = transaction['created_by'];
  return (type == 'cash_in' || type == 'cash_out') &&
      createdBy is String &&
      createdBy.trim().isNotEmpty &&
      transaction['deleted'] != true &&
      !transaction.containsKey('invoice_id');
}

Map<String, dynamic> buildSellerNotification({
  required String sourceType,
  required String sourceId,
  required String sellerId,
  required String sellerName,
  required String tenantId,
  required String shopId,
  required String shopName,
  required String routeId,
  required double amount,
  required String transactionType,
  String? invoiceNumber,
}) {
  final normalizedSellerId = sellerId.trim();
  final normalizedSourceType = sourceType.trim();
  final normalizedSourceId = sourceId.trim();
  if (normalizedSellerId.isEmpty ||
      tenantId.trim().isEmpty ||
      shopId.trim().isEmpty ||
      routeId.trim().isEmpty ||
      normalizedSourceId.isEmpty ||
      normalizedSourceId.contains('/')) {
    throw ArgumentError(
      'Seller notification identity fields must not be empty',
    );
  }
  if (normalizedSourceType != 'invoice' &&
      normalizedSourceType != 'transaction') {
    throw ArgumentError.value(sourceType, 'sourceType');
  }
  if (!amount.isFinite || amount <= 0) {
    throw ArgumentError.value(amount, 'amount');
  }
  if (normalizedSourceType == 'invoice' &&
      (invoiceNumber?.trim().isEmpty ?? true)) {
    throw ArgumentError('Invoice notifications require an invoice number');
  }
  if ((normalizedSourceType == 'invoice' &&
          transactionType != 'cash_out' &&
          transactionType != 'cash_in') ||
      (normalizedSourceType == 'transaction' &&
          transactionType != 'cash_in' &&
          transactionType != 'cash_out')) {
    throw ArgumentError.value(transactionType, 'transactionType');
  }

  return {
    'type': normalizedSourceType,
    'shop_id': shopId.trim(),
    'shop_name': shopName,
    'route_id': routeId.trim(),
    'seller_id': normalizedSellerId,
    'seller_name': sellerName,
    'amount': amount,
    'transaction_type': transactionType,
    'invoice_number': ?invoiceNumber,
    'ref_id': normalizedSourceId,
    'target_role': 'admin',
    'read': false,
    'tenant_id': tenantId.trim(),
    'created_by': normalizedSellerId,
    'created_at': FieldValue.serverTimestamp(),
  };
}

Future<void> writeSellerNotification({
  required FirebaseFirestore db,
  required Map<String, dynamic> data,
}) async {
  final notificationRef = db
      .collection(Collections.notifications)
      .doc(
        sellerNotificationDocumentId(
          sourceType: data['type'] as String? ?? '',
          sourceId: data['ref_id'] as String? ?? '',
        ),
      );
  if (data['type'] == 'transaction') {
    final sourceRef = db
        .collection(Collections.transactions)
        .doc(data['ref_id'] as String? ?? '');
    await db.runTransaction<void>((transaction) async {
      final sourceSnapshot = await transaction.get(sourceRef);
      if (!sourceSnapshot.exists ||
          !isActiveStandaloneTransactionNotificationSource(
            sourceSnapshot.data()!,
          )) {
        return;
      }
      transaction.set(notificationRef, data);
    });
    return;
  }
  await notificationRef.set(data);
}
