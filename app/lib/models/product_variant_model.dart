import 'package:cloud_firestore/cloud_firestore.dart';

class ProductVariantModel {
  final String id;
  final String productId;
  final String variantName;
  final int quantityAvailable;
  final bool active;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ProductVariantModel({
    required this.id,
    required this.productId,
    required this.variantName,
    required this.quantityAvailable,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductVariantModel.fromJson(
    Map<String, dynamic> json,
    String docId,
  ) {
    return ProductVariantModel(
      id: docId,
      productId: json['product_id'] as String? ?? '',
      variantName: json['variant_name'] as String? ?? '',
      quantityAvailable: json['quantity_available'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'variant_name': variantName,
      'quantity_available': quantityAvailable,
      'active': active,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  ProductVariantModel copyWith({
    String? id,
    String? productId,
    String? variantName,
    int? quantityAvailable,
    bool? active,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return ProductVariantModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      variantName: variantName ?? this.variantName,
      quantityAvailable: quantityAvailable ?? this.quantityAvailable,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
