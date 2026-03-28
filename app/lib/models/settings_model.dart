import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsModel {
  final String companyName;
  final String currency;
  final int pairsPerCarton;
  final String? logoUrl;
  final Timestamp updatedAt;

  const SettingsModel({
    required this.companyName,
    required this.currency,
    required this.pairsPerCarton,
    this.logoUrl,
    required this.updatedAt,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      companyName: json['company_name'] as String? ?? 'My Business',
      currency: json['currency'] as String? ?? 'SAR',
      pairsPerCarton: json['pairs_per_carton'] as int? ?? 12,
      logoUrl: json['logo_url'] as String?,
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'company_name': companyName,
        'currency': currency,
        'pairs_per_carton': pairsPerCarton,
        'logo_url': logoUrl,
        'updated_at': updatedAt,
      };
}
