import '../l10n/financial_document_localization.dart';

String triCol(
  String key, {
  String? fallback,
  FinancialDocumentLanguagePair pair =
      FinancialDocumentLanguagePair.englishArabic,
}) => financialDocumentLabel(key, pair, fallback: fallback);

Map<String, String> trilingualLabels(
  Map<String, String> labels, {
  FinancialDocumentLanguagePair pair =
      FinancialDocumentLanguagePair.englishArabic,
}) => {
  for (final entry in labels.entries)
    entry.key: financialDocumentLabel(
      entry.key,
      pair,
      fallback: entry.value,
    ),
};
