import 'app_locale.dart';

enum FinancialDocumentLanguagePair {
  englishArabic('english_arabic', AppLocale.ar),
  englishUrdu('english_urdu', AppLocale.ur);

  const FinancialDocumentLanguagePair(this.firestoreValue, this.secondaryLocale);

  final String firestoreValue;
  final AppLocale secondaryLocale;

  static FinancialDocumentLanguagePair fromJson(Object? value) => switch (
    value
  ) {
    'english_urdu' => FinancialDocumentLanguagePair.englishUrdu,
    _ => FinancialDocumentLanguagePair.englishArabic,
  };
}

String financialDocumentLabel(
  String key,
  FinancialDocumentLanguagePair pair, {
  String? fallback,
}) {
  final english = trRead(key, AppLocale.en);
  final secondary = trRead(key, pair.secondaryLocale);
  if (english == key || secondary == key) return fallback ?? key;
  return '$english\n$secondary';
}
