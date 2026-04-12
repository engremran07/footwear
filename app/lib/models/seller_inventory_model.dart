import 'package:cloud_firestore/cloud_firestore.dart';

class SellerInventoryModel {
  final String id;
  final String sellerId;
  final String sellerName;
  final String productId;
  final String variantId;
  final String variantName;
  final int quantityAvailable;
  final bool active;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const SellerInventoryModel({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.productId,
    required this.variantId,
    required this.variantName,
    required this.quantityAvailable,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SellerInventoryModel.fromJson(
    Map<String, dynamic> json,
    String docId,
  ) {
    return SellerInventoryModel(
      id: docId,
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      variantId: json['variant_id'] as String? ?? '',
      variantName: json['variant_name'] as String? ?? '',
      quantityAvailable: json['quantity_available'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'seller_id': sellerId,
    'seller_name': sellerName,
    'product_id': productId,
    'variant_id': variantId,
    'variant_name': variantName,
    'quantity_available': quantityAvailable,
    'active': active,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}
