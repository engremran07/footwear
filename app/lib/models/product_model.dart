import 'package:cloud_firestore/cloud_firestore.dart';

class ProductModel {
  final String id;
  final String sku;
  final String name;
  final String category;
  final List<String> sizes;
  final String? color;
  final double costPriceDozenPkr;
  final double sellPriceDozenSar;
  final String? imageUrl;
  final int stockCount;
  final bool active;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  const ProductModel({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    this.sizes = const [],
    this.color,
    required this.costPriceDozenPkr,
    required this.sellPriceDozenSar,
    this.imageUrl,
    required this.stockCount,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  double get costPerPairPkr => costPriceDozenPkr / 12;
  double get sellPerPairSar => sellPriceDozenSar / 12;

  factory ProductModel.fromJson(Map<String, dynamic> json, String docId) {
    return ProductModel(
      id: docId,
      sku: json['sku'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      sizes: List<String>.from(json['sizes'] as List? ?? []),
      color: json['color'] as String?,
      costPriceDozenPkr: (json['cost_price_dozen_pkr'] as num?)?.toDouble() ??
          (json['cost_price'] as num?)?.toDouble() ??
          0.0,
      sellPriceDozenSar: (json['sell_price_dozen_sar'] as num?)?.toDouble() ??
          (json['sell_price'] as num?)?.toDouble() ??
          0.0,
      imageUrl: json['image_url'] as String?,
      stockCount: json['stock_count'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] as Timestamp? ?? Timestamp.now(),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'name': name,
        'category': category,
        'sizes': sizes,
        'color': color,
        'cost_price_dozen_pkr': costPriceDozenPkr,
        'sell_price_dozen_sar': sellPriceDozenSar,
        'image_url': imageUrl,
        'stock_count': stockCount,
        'active': active,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  ProductModel copyWith({
    String? id,
    String? sku,
    String? name,
    String? category,
    List<String>? sizes,
    String? color,
    double? costPriceDozenPkr,
    double? sellPriceDozenSar,
    String? imageUrl,
    int? stockCount,
    bool? active,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) {
    return ProductModel(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      category: category ?? this.category,
      sizes: sizes ?? this.sizes,
      color: color ?? this.color,
      costPriceDozenPkr: costPriceDozenPkr ?? this.costPriceDozenPkr,
      sellPriceDozenSar: sellPriceDozenSar ?? this.sellPriceDozenSar,
      imageUrl: imageUrl ?? this.imageUrl,
      stockCount: stockCount ?? this.stockCount,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
