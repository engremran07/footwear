/// Bilingual (EN + single RTL) column headers for export reports.
///
/// Always active in all exports (PDF / Excel / image) regardless of the
/// app interface language. The interface locale is a separate concern —
/// these strings only appear in exported document column headings.
library;

/// Returns a bilingual column header "English\nRTL" for the given [key].
///
/// Falls back to [fallback] (typically the tr() value) when the key
/// has no hardcoded mapping.
String triCol(String key, [String? fallback]) {
  return _trilingual[key] ?? fallback ?? key;
}

/// Applies bilingual headers to a labels map used by PDF builders.
///
/// Only keys in [_columnKeys] are replaced; document-level labels
/// (account_statement, report_date, page, etc.) are left unchanged so they
/// continue to follow the current interface locale.
Map<String, String> trilingualLabels(Map<String, String> labels) {
  return labels.map((key, value) {
    final tri = _columnKeys.contains(key) ? _trilingual[key] : null;
    return MapEntry(key, tri ?? value);
  });
}

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

const _trilingual = <String, String>{
  'date': 'Date\nتاریخ',
  'description': 'Description\nتفصیل',
  'entry_by': 'Entry By\nبواسطة',
  'debit': 'Debit\nفاتورة',
  'credit': 'Credit\nواصل',
  'running_balance': 'Balance\nباقی',
  'type': 'Type\nالنوع',
  'amount': 'Amount\nالمبلغ',
  'name': 'Name\nالاسم',
  'route': 'Route\nمنطقة',
  'phone': 'Phone\nالهاتف',
  'area': 'Area\nالمنطقة',
  'balance': 'Balance\nباقی',
  'shop': 'Shop\nمحل',
  'shop_name': 'Shop Name\nاسم المحل',
  'stock_sold': 'Sold\nمباع',
  'revenue': 'Revenue\nالإيرادات',
  'outstanding': 'Outstanding\nمستحق',
  'variant_name': 'Variant Name\nاسم المتغير',
  'stock_pairs': 'Stock (Pairs)\nالمخزون (أزواج)',
  'bad_debt_amount': 'Bad Debt\nالدين المعدوم',
  'item_number': 'Item\nالمنتج',
  'size': 'Size\nالمقاس',
  'color': 'Color\nاللون',
  'qty': 'Qty\nالكمية',
  'unit_price': 'Price\nالسعر',
  'total': 'Total\nالإجمالي',
  'lbl_variant_name': 'Variant\nالمتغير',
  'lbl_quantity_available': 'Stock\nالمخزون',
};
