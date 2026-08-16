import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsModel {
  final String tenantId;
  final String companyName;
  final String currency;
  final int pairsPerCarton;
  final bool requireAdminApprovalForSellerTransactionEdits;

  /// Base64-encoded PNG/JPEG logo, stored directly in Firestore.
  /// Use [logoBytes] to get the decoded bytes for Image.memory() or PDF.
  final String? logoBase64;
  final Timestamp updatedAt;

  const SettingsModel({
    this.tenantId = '__global__',
    required this.companyName,
    required this.currency,
    required this.pairsPerCarton,
    this.requireAdminApprovalForSellerTransactionEdits = false,
    this.logoBase64,
    required this.updatedAt,
  }) : assert(pairsPerCarton > 0, 'pairsPerCarton must be greater than 0');

  SettingsModel copyWith({
    String? tenantId,
    String? companyName,
    String? currency,
    int? pairsPerCarton,
    bool? requireAdminApprovalForSellerTransactionEdits,
    String? logoBase64,
    bool clearLogoBase64 = false,
    Timestamp? updatedAt,
  }) {
    return SettingsModel(
      tenantId: tenantId ?? this.tenantId,
      companyName: companyName ?? this.companyName,
      currency: currency ?? this.currency,
      pairsPerCarton: pairsPerCarton ?? this.pairsPerCarton,
      requireAdminApprovalForSellerTransactionEdits:
          requireAdminApprovalForSellerTransactionEdits ??
          this.requireAdminApprovalForSellerTransactionEdits,
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
    final tenantId = json['tenant_id'] as String? ?? '__global__';
    return SettingsModel(
      tenantId: tenantId,
      companyName: json['company_name'] as String? ?? 'My Business',
      currency: json['currency'] as String? ?? 'SAR',
      pairsPerCarton: json['pairs_per_carton'] as int? ?? 12,
      requireAdminApprovalForSellerTransactionEdits:
          json['require_admin_approval_for_seller_transaction_edits']
              as bool? ??
          false,
      logoBase64: json['logo_base64'] as String?,
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'company_name': companyName,
    'currency': currency,
    'pairs_per_carton': pairsPerCarton,
    'require_admin_approval_for_seller_transaction_edits':
        requireAdminApprovalForSellerTransactionEdits,
    'logo_base64': logoBase64,
    'updated_at': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsModel &&
          other.tenantId == tenantId &&
          other.companyName == companyName &&
          other.currency == currency &&
          other.pairsPerCarton == pairsPerCarton &&
          other.requireAdminApprovalForSellerTransactionEdits ==
              requireAdminApprovalForSellerTransactionEdits &&
          other.logoBase64 == logoBase64 &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(
    tenantId,
    companyName,
    currency,
    pairsPerCarton,
    requireAdminApprovalForSellerTransactionEdits,
    logoBase64,
    updatedAt,
  );
}
