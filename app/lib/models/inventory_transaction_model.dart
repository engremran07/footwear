import 'package:cloud_firestore/cloud_firestore.dart';

/// Audit-trail document written to `inventory_transactions` whenever stock moves.
class InventoryTransactionModel {
  static const String typeTransferOut = 'transfer_out';
  static const String typeReturnToWarehouse = 'return_to_warehouse';
  static const String typeReturnFromShop = 'return_from_shop';
  static const String typeStockAdjustment = 'stock_adjustment';

  final String id;
  final String type;
  final String sellerId;
  final String sellerName;
  final String variantId;
  final String variantName;
  final String productId;
  final int quantity;
  final String? notes;
  final String createdBy;
  final Timestamp createdAt;

  const InventoryTransactionModel({
    required this.id,
    required this.type,
    required this.sellerId,
    required this.sellerName,
    required this.variantId,
    required this.variantName,
    required this.productId,
    required this.quantity,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  InventoryTransactionModel copyWith({
    String? id,
    String? type,
    String? sellerId,
    String? sellerName,
    String? variantId,
    String? variantName,
    String? productId,
    int? quantity,
    String? notes,
    bool clearNotes = false,
    String? createdBy,
    Timestamp? createdAt,
  }) {
    return InventoryTransactionModel(
      id: id ?? this.id,
      type: type ?? this.type,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      variantId: variantId ?? this.variantId,
      variantName: variantName ?? this.variantName,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      notes: clearNotes ? null : (notes ?? this.notes),
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory InventoryTransactionModel.fromJson(
    Map<String, dynamic> json,
    String docId,
  ) {
    return InventoryTransactionModel(
      id: docId,
      type: json['type'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      variantId: json['variant_id'] as String? ?? '',
      variantName: json['variant_name'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'seller_id': sellerId,
    'seller_name': sellerName,
    'variant_id': variantId,
    'variant_name': variantName,
    'product_id': productId,
    'quantity': quantity,
    'notes': notes,
    'created_by': createdBy,
    'created_at': createdAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryTransactionModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
