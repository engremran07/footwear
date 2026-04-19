/// Hard-coded trilingual (EN / AR / UR) column headers for export reports.
///
/// Always active — no settings toggle. English on first line,
/// Arabic / Urdu on second line (or just one if AR == UR).
library;

/// Returns a trilingual column header for the given l10n [key].
///
/// Format: `"English\nالعربية / اردو"` when AR ≠ UR,
///         `"English\nفاتورة"` when AR == UR.
///
/// Falls back to [fallback] (typically the `tr()` value) when the key
/// has no hardcoded trilingual mapping.
String triCol(String key, [String? fallback]) {
  return _trilingual[key] ?? fallback ?? key;
}

/// Applies trilingual headers to a labels map used by PDF builders.
///
/// Only keys in [_columnKeys] are replaced with trilingual values.
/// Document-level labels (account_statement, report_date, page, etc.)
/// are left unchanged so they follow the current locale.
Map<String, String> trilingualLabels(Map<String, String> labels) {
  return labels.map((key, value) {
    final tri = _columnKeys.contains(key) ? _trilingual[key] : null;
    return MapEntry(key, tri ?? value);
  });
}

// ── Column keys eligible for trilingual treatment ──────────────────────

const _columnKeys = <String>{
  'date',
  'description',
  'entry_by',
  'debit',
  'credit',
  'running_balance',
  'name',
  'route',
  'phone',
  'area',
  'balance',
  'type',
  'amount',
  'shop',
  'shop_name',
  'stock_sold',
  'revenue',
  'outstanding',
  'variant_name',
  'stock_pairs',
  'bad_debt_amount',
  'item_number',
  'size',
  'color',
  'qty',
  'unit_price',
  'total',
  'lbl_variant_name',
  'lbl_quantity_available',
};

// ── Trilingual map ─────────────────────────────────────────────────────
// Key → "English\nArabic / Urdu" (or just Arabic when AR == UR).

const _trilingual = <String, String>{
  // ── Ledger / transaction columns ──
  'date': 'Date\nالتاريخ / تاریخ',
  'description': 'Description\nالوصف / تفصیل',
  'entry_by': 'Entry By\nأدخل بواسطة / اندراج از',
  'debit': 'Debit\nفاتورة',
  'credit': 'Credit\nواصل',
  'running_balance': 'Balance\nالرصيد / بقایا',
  'type': 'Type\nالنوع / قسم',
  'amount': 'Amount\nالمبلغ / رقم',

  // ── Shop / route columns ──
  'name': 'Name\nالاسم / نام',
  'route': 'Route\nمنطقة / علاقہ',
  'phone': 'Phone\nالهاتف / فون',
  'area': 'Area\nالمنطقة / علاقہ',
  'balance': 'Balance\nالرصيد / بقایا',
  'shop': 'Shop\nمحل / دکان',
  'shop_name': 'Shop Name\nاسم المحل / دکان کا نام',

  // ── Seller report columns ──
  'stock_sold': 'Sold\nمباع / فروخت',
  'revenue': 'Revenue\nالإيرادات / آمدنی',
  'outstanding': 'Outstanding\nمستحق / واجب الادا',

  // ── Inventory columns ──
  'variant_name': 'Variant Name\nاسم المتغير / ویریئنٹ کا نام',
  'stock_pairs': 'Stock (Pairs)\nالمخزون (أزواج) / اسٹاک (جوڑے)',

  // ── Bad debt column ──
  'bad_debt_amount': 'Bad Debt\nالدين المعدوم / ناقابل وصول قرض',

  // ── Invoice detail columns ──
  'item_number': 'Item\nالمنتج / پروڈکٹ',
  'size': 'Size\nالمقاس / سائز',
  'color': 'Color\nاللون / رنگ',
  'qty': 'Qty\nالكمية / مقدار',
  'unit_price': 'Price\nالسعر / قیمت',
  'total': 'Total\nالإجمالي / کل',

  // ── Inventory screen columns ──
  'lbl_variant_name': 'Variant\nالمتغير / ویریئنٹ',
  'lbl_quantity_available': 'Stock\nالمخزون / اسٹاک',
};
