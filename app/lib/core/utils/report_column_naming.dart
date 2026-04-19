import '../l10n/app_locale.dart';

const Map<String, String> _headerTokenToArabic = {
  'date': 'التاريخ',
  'description': 'التفاصيل',
  'entry by': 'بواسطة',
  'credit': 'فاتورة',
  'debit': 'واصل',
  'balance': 'الباقي',
  'running balance': 'الباقي',
};

const Map<String, String> _labelKeyToArabic = {
  'date': 'التاريخ',
  'description': 'التفاصيل',
  'entry_by': 'بواسطة',
  'credit': 'فاتورة',
  'debit': 'واصل',
  'running_balance': 'الباقي',
};

bool shouldUseArabicColumnNamesInEnglish({
  required AppLocale locale,
  required bool enabled,
}) {
  return enabled && locale == AppLocale.en;
}

String _normalizeHeaderToken(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String appendArabicColumnName(String header) {
  final token = _normalizeHeaderToken(header);
  final arabic = _headerTokenToArabic[token];
  if (arabic == null || header.contains(arabic)) return header;
  return '$header / $arabic';
}

List<String> applyArabicColumnNamesToHeaders(
  List<String> headers, {
  required AppLocale locale,
  required bool enabled,
}) {
  if (!shouldUseArabicColumnNamesInEnglish(locale: locale, enabled: enabled)) {
    return headers;
  }
  return headers.map(appendArabicColumnName).toList(growable: false);
}

Map<String, String> applyArabicColumnNamesToLabels(
  Map<String, String> labels, {
  required AppLocale locale,
  required bool enabled,
}) {
  if (!shouldUseArabicColumnNamesInEnglish(locale: locale, enabled: enabled)) {
    return labels;
  }
  final updated = Map<String, String>.from(labels);
  for (final entry in _labelKeyToArabic.entries) {
    final current = updated[entry.key];
    if (current == null) continue;
    updated[entry.key] = appendArabicColumnName(current);
  }
  return updated;
}
