import 'package:cloud_firestore/cloud_firestore.dart';

// =============================================================================
// NotificationModel — in-app notification written by provider notifiers after
// financial events (transactions, invoices). Admin-only feed, Firestore-listener
// based, NO FCM, NO Cloud Functions (Spark free tier).
//
// WRITE PIPELINE:
//   TransactionNotifier / InvoiceNotifier → after batch.commit() → best-effort
//   write to Collections.notifications (try/catch, non-critical).
//
// FIELDS:
//   type          : 'transaction' | 'invoice'
//   shopId        : shop that the event belongs to
//   shopName      : denormalized display name
//   routeId       : route context for filtering
//   sellerId      : UID of the seller who triggered the event
//   sellerName    : denormalized display name
//   amount        : monetary amount (always positive)
//   transactionType: 'cash_in' | 'cash_out' | 'return' | 'payment' | 'write_off'
//   invoiceNumber : set for type=='invoice' (null otherwise)
//   refId         : Firestore doc ID of the source transaction / invoice
//   targetRole    : 'admin' — the role that should see this notification
//   read          : false by default; toggled by admin via NotificationNotifier
//   readAt        : timestamp when read was set to true
//   createdBy     : UID of the user who triggered the event
//   createdAt     : server timestamp
// =============================================================================
class NotificationModel {
  final String id;
  final String type; // 'transaction' | 'invoice'
  final String shopId;
  final String shopName;
  final String routeId;
  final String sellerId;
  final String sellerName;
  final double amount;
  final String transactionType;
  final String? invoiceNumber;
  final String refId;
  final String targetRole; // 'admin'
  final bool read;
  final Timestamp? readAt;
  final String createdBy;
  final Timestamp createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.shopId,
    required this.shopName,
    required this.routeId,
    required this.sellerId,
    required this.sellerName,
    required this.amount,
    required this.transactionType,
    this.invoiceNumber,
    required this.refId,
    required this.targetRole,
    this.read = false,
    this.readAt,
    required this.createdBy,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json, String docId) {
    return NotificationModel(
      id: docId,
      type: json['type'] as String? ?? 'transaction',
      shopId: json['shop_id'] as String? ?? '',
      shopName: json['shop_name'] as String? ?? '',
      routeId: json['route_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      transactionType: json['transaction_type'] as String? ?? 'cash_out',
      invoiceNumber: json['invoice_number'] as String?,
      refId: json['ref_id'] as String? ?? '',
      targetRole: json['target_role'] as String? ?? 'admin',
      read: json['read'] as bool? ?? false,
      readAt: json['read_at'] as Timestamp?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'shop_id': shopId,
    'shop_name': shopName,
    'route_id': routeId,
    'seller_id': sellerId,
    'seller_name': sellerName,
    'amount': amount,
    'transaction_type': transactionType,
    if (invoiceNumber != null) 'invoice_number': invoiceNumber,
    'ref_id': refId,
    'target_role': targetRole,
    'read': read,
    if (readAt != null) 'read_at': readAt,
    'created_by': createdBy,
    'created_at': createdAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is NotificationModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
