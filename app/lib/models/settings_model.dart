import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/l10n/financial_document_localization.dart';

class InvoiceHeaderConfig {
  final String nameEn;
  final String nameAr;
  final String nameUr;
  final String subtitleEn;
  final String subtitleAr;
  final String subtitleUr;
  final String addressEn;
  final String addressAr;
  final String addressUr;
  final String phone;
  final String receiptPhone2;
  final String receiptPhone3;
  final String email;
  final String taxNumber;
  final String commercialRegistrationNumber;
  final String template;
  final String accentColor;
  final String titleScale;
  final FinancialDocumentLanguagePair documentLanguagePair;
  final Set<String> visibleFields;

  const InvoiceHeaderConfig({
    this.nameEn = '',
    this.nameAr = '',
    this.nameUr = '',
    this.subtitleEn = '',
    this.subtitleAr = '',
    this.subtitleUr = '',
    this.addressEn = '',
    this.addressAr = '',
    this.addressUr = '',
    this.phone = '',
    this.receiptPhone2 = '',
    this.receiptPhone3 = '',
    this.email = '',
    this.taxNumber = '',
    this.commercialRegistrationNumber = '',
    this.template = 'classic',
    this.accentColor = '#315C4C',
    this.titleScale = 'normal',
    this.documentLanguagePair = FinancialDocumentLanguagePair.englishArabic,
    this.visibleFields = const {
      'logo',
      'phone',
      'email',
      'tax_number',
      'commercial_registration_number',
    },
  });

  factory InvoiceHeaderConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const InvoiceHeaderConfig();
    final rawVisibleFields = json['visible_fields'] as List<dynamic>?;
    return InvoiceHeaderConfig(
      nameEn: json['name_en'] as String? ?? '',
      nameAr: json['name_ar'] as String? ?? '',
      nameUr: json['name_ur'] as String? ?? '',
      subtitleEn: json['subtitle_en'] as String? ?? '',
      subtitleAr: json['subtitle_ar'] as String? ?? '',
      subtitleUr: json['subtitle_ur'] as String? ?? '',
      addressEn: json['address_en'] as String? ?? '',
      addressAr: json['address_ar'] as String? ?? '',
      addressUr: json['address_ur'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      receiptPhone2: json['receipt_phone_2'] as String? ?? '',
      receiptPhone3: json['receipt_phone_3'] as String? ?? '',
      email: json['email'] as String? ?? '',
      taxNumber: json['tax_number'] as String? ?? '',
      commercialRegistrationNumber:
          json['commercial_registration_number'] as String? ?? '',
      template: json['template'] as String? ?? 'classic',
      accentColor: json['accent_color'] as String? ?? '#315C4C',
      titleScale: switch (json['title_scale']) {
        'small' => 'small',
        'large' => 'large',
        _ => 'normal',
      },
      documentLanguagePair: FinancialDocumentLanguagePair.fromJson(
        json['document_language_pair'],
      ),
      visibleFields: rawVisibleFields == null
          ? const {
              'logo',
              'phone',
              'email',
              'tax_number',
              'commercial_registration_number',
            }
          : rawVisibleFields.whereType<String>().toSet(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name_en': nameEn,
    'name_ar': nameAr,
    'name_ur': nameUr,
    'subtitle_en': subtitleEn,
    'subtitle_ar': subtitleAr,
    'subtitle_ur': subtitleUr,
    'address_en': addressEn,
    'address_ar': addressAr,
    'address_ur': addressUr,
    'phone': phone,
    'receipt_phone_2': receiptPhone2,
    'receipt_phone_3': receiptPhone3,
    'email': email,
    'tax_number': taxNumber,
    'commercial_registration_number': commercialRegistrationNumber,
    'template': template,
    'accent_color': accentColor,
    'title_scale': titleScale,
    'document_language_pair': documentLanguagePair.firestoreValue,
    'visible_fields': visibleFields.toList()..sort(),
  };

  InvoiceHeaderConfig copyWith({
    String? nameEn,
    String? nameAr,
    String? nameUr,
    String? subtitleEn,
    String? subtitleAr,
    String? subtitleUr,
    String? addressEn,
    String? addressAr,
    String? addressUr,
    String? phone,
    String? receiptPhone2,
    String? receiptPhone3,
    String? email,
    String? taxNumber,
    String? commercialRegistrationNumber,
    String? template,
    String? accentColor,
    String? titleScale,
    FinancialDocumentLanguagePair? documentLanguagePair,
    Set<String>? visibleFields,
  }) => InvoiceHeaderConfig(
    nameEn: nameEn ?? this.nameEn,
    nameAr: nameAr ?? this.nameAr,
    nameUr: nameUr ?? this.nameUr,
    subtitleEn: subtitleEn ?? this.subtitleEn,
    subtitleAr: subtitleAr ?? this.subtitleAr,
    subtitleUr: subtitleUr ?? this.subtitleUr,
    addressEn: addressEn ?? this.addressEn,
    addressAr: addressAr ?? this.addressAr,
    addressUr: addressUr ?? this.addressUr,
    phone: phone ?? this.phone,
    receiptPhone2: receiptPhone2 ?? this.receiptPhone2,
    receiptPhone3: receiptPhone3 ?? this.receiptPhone3,
    email: email ?? this.email,
    taxNumber: taxNumber ?? this.taxNumber,
    commercialRegistrationNumber:
        commercialRegistrationNumber ?? this.commercialRegistrationNumber,
    template: template ?? this.template,
    accentColor: accentColor ?? this.accentColor,
    titleScale: titleScale ?? this.titleScale,
    documentLanguagePair: documentLanguagePair ?? this.documentLanguagePair,
    visibleFields: visibleFields ?? this.visibleFields,
  );
}

class SettingsModel {
  static const maxLogoBase64Bytes = 50 * 1024;

  final String tenantId;
  final String currency;
  final int pairsPerCarton;
  final bool requireAdminApprovalForSellerTransactionEdits;
  final bool allowNonStockInvoices;
  final InvoiceHeaderConfig invoiceHeader;

  /// Base64-encoded lossless PNG logo, stored directly in Firestore.
  /// Use [logoBytes] to get the decoded bytes for Image.memory() or PDF.
  final String? logoBase64;
  final Timestamp updatedAt;

  const SettingsModel({
    this.tenantId = '__global__',
    required this.currency,
    required this.pairsPerCarton,
    this.requireAdminApprovalForSellerTransactionEdits = false,
    this.allowNonStockInvoices = false,
    this.invoiceHeader = const InvoiceHeaderConfig(),
    this.logoBase64,
    required this.updatedAt,
  }) : assert(pairsPerCarton > 0, 'pairsPerCarton must be greater than 0');

  String get companyName {
    for (final name in [
      invoiceHeader.nameEn,
      invoiceHeader.nameAr,
      invoiceHeader.nameUr,
    ]) {
      if (name.trim().isNotEmpty) return name.trim();
    }
    return 'My Business';
  }

  SettingsModel copyWith({
    String? tenantId,
    String? currency,
    int? pairsPerCarton,
    bool? requireAdminApprovalForSellerTransactionEdits,
    bool? allowNonStockInvoices,
    InvoiceHeaderConfig? invoiceHeader,
    String? logoBase64,
    bool clearLogoBase64 = false,
    Timestamp? updatedAt,
  }) {
    return SettingsModel(
      tenantId: tenantId ?? this.tenantId,
      currency: currency ?? this.currency,
      pairsPerCarton: pairsPerCarton ?? this.pairsPerCarton,
      requireAdminApprovalForSellerTransactionEdits:
          requireAdminApprovalForSellerTransactionEdits ??
          this.requireAdminApprovalForSellerTransactionEdits,
      allowNonStockInvoices:
          allowNonStockInvoices ?? this.allowNonStockInvoices,
      invoiceHeader: invoiceHeader ?? this.invoiceHeader,
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

  Map<String, dynamic> get invoiceHeaderSnapshot => {
    ...invoiceHeader.toJson(),
    if (logoBase64 != null) 'logo_base64': logoBase64,
  };

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    final tenantId = json['tenant_id'] as String? ?? '__global__';
    final header = InvoiceHeaderConfig.fromJson(
      json['invoice_header'] as Map<String, dynamic>?,
    );
    final legacyName = (json['company_name'] as String? ?? '').trim();
    final canonicalHeader =
        header.nameEn.trim().isEmpty &&
            header.nameAr.trim().isEmpty &&
            header.nameUr.trim().isEmpty &&
            legacyName.isNotEmpty
        ? header.copyWith(nameEn: legacyName)
        : header;
    return SettingsModel(
      tenantId: tenantId,
      currency: json['currency'] as String? ?? 'SAR',
      pairsPerCarton: json['pairs_per_carton'] as int? ?? 12,
      requireAdminApprovalForSellerTransactionEdits:
          json['require_admin_approval_for_seller_transaction_edits']
              as bool? ??
          false,
      allowNonStockInvoices: json['allow_non_stock_invoices'] as bool? ?? false,
      invoiceHeader: canonicalHeader,
      logoBase64: json['logo_base64'] as String?,
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'currency': currency,
    'pairs_per_carton': pairsPerCarton,
    'require_admin_approval_for_seller_transaction_edits':
        requireAdminApprovalForSellerTransactionEdits,
    'allow_non_stock_invoices': allowNonStockInvoices,
    'invoice_header': invoiceHeader.toJson(),
    'logo_base64': logoBase64,
    'updated_at': updatedAt,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsModel &&
          other.tenantId == tenantId &&
          other.currency == currency &&
          other.pairsPerCarton == pairsPerCarton &&
          other.requireAdminApprovalForSellerTransactionEdits ==
              requireAdminApprovalForSellerTransactionEdits &&
          other.allowNonStockInvoices == allowNonStockInvoices &&
          other.invoiceHeader.toJson().toString() ==
              invoiceHeader.toJson().toString() &&
          other.logoBase64 == logoBase64 &&
          other.updatedAt == updatedAt);

  @override
  int get hashCode => Object.hash(
    tenantId,
    currency,
    pairsPerCarton,
    requireAdminApprovalForSellerTransactionEdits,
    allowNonStockInvoices,
    invoiceHeader.toJson().toString(),
    logoBase64,
    updatedAt,
  );
}
