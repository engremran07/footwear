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
}
