import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsModel {
  final String id; // always "global"
  final String companyName;
  final String currencyPrimary;
  final String currencySecondary;
  final double taxRate;
  final int lowStockThreshold;
  final String? logoUrl;
  // Contact
  final String companyAddress;
  final String companyPhone;
  // Worker defaults
  final double defaultPkRate;
  final double defaultKsaRate;
  final double exchangeRatePkrToSar;
  // Configurable lists
  final List<String> productCategories;
  final List<String> expenseCategories;
  final List<String> qcRejectReasons;
  final Timestamp updatedAt;

  static const defaultProductCategories = <String>[
    'Formal',
    'Casual',
    'Sports',
    'Boots',
    'Sandals',
    'Kids',
    'Safety',
  ];
  static const defaultExpenseCategories = <String>[
    'rent',
    'utilities',
    'transport',
    'marketing',
    'materials',
    'bad_debt',
    'other',
  ];
  static const defaultQcRejectReasons = <String>[
    'stitching_issue',
    'sole_defect',
    'size_mismatch',
    'cosmetic_damage',
    'material_defect',
    'other',
  ];

  const SettingsModel({
    required this.id,
    required this.companyName,
    required this.currencyPrimary,
    required this.currencySecondary,
    required this.taxRate,
    required this.lowStockThreshold,
    this.logoUrl,
    required this.companyAddress,
    required this.companyPhone,
    required this.defaultPkRate,
    required this.defaultKsaRate,
    required this.exchangeRatePkrToSar,
    required this.productCategories,
    required this.expenseCategories,
    required this.qcRejectReasons,
    required this.updatedAt,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json, String docId) {
    List<String> strList(String key, List<String> fallback) {
      final raw = json[key];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return List<String>.from(fallback);
    }

    return SettingsModel(
      id: docId,
      companyName: json['company_name'] as String? ?? '',
      currencyPrimary: json['currency_primary'] as String? ?? 'SAR',
      currencySecondary: json['currency_secondary'] as String? ?? 'PKR',
      taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 0.0,
      lowStockThreshold: json['low_stock_threshold'] as int? ?? 10,
      logoUrl: json['logo_url'] as String?,
      companyAddress: json['company_address'] as String? ?? '',
      companyPhone: json['company_phone'] as String? ?? '',
      defaultPkRate: (json['default_pk_rate'] as num?)?.toDouble() ?? 85.0,
      defaultKsaRate: (json['default_ksa_rate'] as num?)?.toDouble() ?? 15.0,
      exchangeRatePkrToSar:
          (json['exchange_rate_pkr_to_sar'] as num?)?.toDouble() ?? 0.013,
      productCategories:
          strList('product_categories', defaultProductCategories),
      expenseCategories:
          strList('expense_categories', defaultExpenseCategories),
      qcRejectReasons: strList('qc_reject_reasons', defaultQcRejectReasons),
      updatedAt: json['updated_at'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'company_name': companyName,
        'currency_primary': currencyPrimary,
        'currency_secondary': currencySecondary,
        'tax_rate': taxRate,
        'low_stock_threshold': lowStockThreshold,
        'logo_url': logoUrl,
        'company_address': companyAddress,
        'company_phone': companyPhone,
        'default_pk_rate': defaultPkRate,
        'default_ksa_rate': defaultKsaRate,
        'exchange_rate_pkr_to_sar': exchangeRatePkrToSar,
        'product_categories': productCategories,
        'expense_categories': expenseCategories,
        'qc_reject_reasons': qcRejectReasons,
        'updated_at': updatedAt,
      };

  SettingsModel copyWith({
    String? id,
    String? companyName,
    String? currencyPrimary,
    String? currencySecondary,
    double? taxRate,
    int? lowStockThreshold,
    String? logoUrl,
    String? companyAddress,
    String? companyPhone,
    double? defaultPkRate,
    double? defaultKsaRate,
    double? exchangeRatePkrToSar,
    List<String>? productCategories,
    List<String>? expenseCategories,
    List<String>? qcRejectReasons,
    Timestamp? updatedAt,
  }) {
    return SettingsModel(
      id: id ?? this.id,
      companyName: companyName ?? this.companyName,
      currencyPrimary: currencyPrimary ?? this.currencyPrimary,
      currencySecondary: currencySecondary ?? this.currencySecondary,
      taxRate: taxRate ?? this.taxRate,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      logoUrl: logoUrl ?? this.logoUrl,
      companyAddress: companyAddress ?? this.companyAddress,
      companyPhone: companyPhone ?? this.companyPhone,
      defaultPkRate: defaultPkRate ?? this.defaultPkRate,
      defaultKsaRate: defaultKsaRate ?? this.defaultKsaRate,
      exchangeRatePkrToSar: exchangeRatePkrToSar ?? this.exchangeRatePkrToSar,
      productCategories: productCategories ?? this.productCategories,
      expenseCategories: expenseCategories ?? this.expenseCategories,
      qcRejectReasons: qcRejectReasons ?? this.qcRejectReasons,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
