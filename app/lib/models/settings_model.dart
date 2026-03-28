import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsModel {
  final String companyName;
  final String currency;
  final int pairsPerCarton;

  /// Base64-encoded PNG/JPEG logo, stored directly in Firestore.
  /// Use [logoBytes] to get the decoded bytes for Image.memory() or PDF.
  final String? logoBase64;
  final Timestamp updatedAt;

  const SettingsModel({
    required this.companyName,
    required this.currency,
    required this.pairsPerCarton,
    this.logoBase64,
    required this.updatedAt,
  });

  /// Decoded logo bytes ready for Image.memory() and PDF generation.
  /// Returns null when no logo has been uploaded.
  Uint8List? get logoBytes =>
      logoBase64 != null ? base64Decode(logoBase64!) : null;

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      companyName: json['company_name'] as String? ?? 'My Business',
      currency: json['currency'] as String? ?? 'SAR',
      pairsPerCarton: json['pairs_per_carton'] as int? ?? 12,
      logoBase64: json['logo_base64'] as String?,
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'company_name': companyName,
        'currency': currency,
        'pairs_per_carton': pairsPerCarton,
        'logo_base64': logoBase64,
        'updated_at': updatedAt,
      };
}
