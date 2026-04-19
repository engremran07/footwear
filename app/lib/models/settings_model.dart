import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsModel {
  final String companyName;
  final String currency;
  final int pairsPerCarton;
  final bool requireAdminApprovalForSellerTransactionEdits;
  final bool showArabicColumnNamesInEnglishReports;

  /// Base64-encoded PNG/JPEG logo, stored directly in Firestore.
  /// Use [logoBytes] to get the decoded bytes for Image.memory() or PDF.
  final String? logoBase64;
  final Timestamp updatedAt;

  const SettingsModel({
    required this.companyName,
    required this.currency,
    required this.pairsPerCarton,
    this.requireAdminApprovalForSellerTransactionEdits = false,
    this.showArabicColumnNamesInEnglishReports = false,
    this.logoBase64,
    required this.updatedAt,
  }) : assert(pairsPerCarton > 0, 'pairsPerCarton must be greater than 0');

  SettingsModel copyWith({
    String? companyName,
    String? currency,
    int? pairsPerCarton,
    bool? requireAdminApprovalForSellerTransactionEdits,
    bool? showArabicColumnNamesInEnglishReports,
    String? logoBase64,
    bool clearLogoBase64 = false,
    Timestamp? updatedAt,
  }) {
    return SettingsModel(
      companyName: companyName ?? this.companyName,
      currency: currency ?? this.currency,
      pairsPerCarton: pairsPerCarton ?? this.pairsPerCarton,
      requireAdminApprovalForSellerTransactionEdits:
          requireAdminApprovalForSellerTransactionEdits ??
          this.requireAdminApprovalForSellerTransactionEdits,
      showArabicColumnNamesInEnglishReports:
          showArabicColumnNamesInEnglishReports ??
          this.showArabicColumnNamesInEnglishReports,
      logoBase64: clearLogoBase64 ? null : (logoBase64 ?? this.logoBase64),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Decoded logo bytes ready for Image.memory() and PDF generation.
  /// Returns null when no logo has been uploaded or if the base64 is corrupt.
  Uint8List? get logoBytes {
    if (logoBase64 == null) return null;
    try {
      return base64Decode(logoBase64!);
    } catch (_) {
      return null; // I-23: corrupt base64 must not crash the app
    }
  }

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      companyName: json['company_name'] as String? ?? 'My Business',
      currency: json['currency'] as String? ?? 'SAR',
      pairsPerCarton: json['pairs_per_carton'] as int? ?? 12,
      requireAdminApprovalForSellerTransactionEdits:
          json['require_admin_approval_for_seller_transaction_edits']
              as bool? ??
          false,
      showArabicColumnNamesInEnglishReports:
          json['show_arabic_column_names_in_english_reports'] as bool? ?? false,
      logoBase64: json['logo_base64'] as String?,
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'company_name': companyName,
    'currency': currency,
    'pairs_per_carton': pairsPerCarton,
    'require_admin_approval_for_seller_transaction_edits':
        requireAdminApprovalForSellerTransactionEdits,
    'show_arabic_column_names_in_english_reports':
        showArabicColumnNamesInEnglishReports,
    'logo_base64': logoBase64,
    'updated_at': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsModel &&
          other.companyName == companyName &&
          other.currency == currency &&
          other.pairsPerCarton == pairsPerCarton &&
          other.requireAdminApprovalForSellerTransactionEdits ==
              requireAdminApprovalForSellerTransactionEdits &&
          other.showArabicColumnNamesInEnglishReports ==
              showArabicColumnNamesInEnglishReports &&
          other.logoBase64 == logoBase64 &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(
    companyName,
    currency,
    pairsPerCarton,
    requireAdminApprovalForSellerTransactionEdits,
    showArabicColumnNamesInEnglishReports,
    logoBase64,
    updatedAt,
  );
}
