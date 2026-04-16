import 'package:cloud_firestore/cloud_firestore.dart';

class ProductModel {
  final String id;
  final String name;
  final String category;
  final String? imageUrl;
  final bool active;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ProductModel({
    required this.id,
    required this.name,
    required this.category,
    this.imageUrl,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  ProductModel copyWith({
    String? id,
    String? name,
    String? category,
    String? imageUrl,
    bool clearImageUrl = false,
    bool? active,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json, String docId) {
    return ProductModel(
      id: docId,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'image_url': imageUrl,
    'active': active,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ProductModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
