import 'dart:typed_data';
import '../l10n/app_locale.dart';
import 'name_resolver.dart';

/// Single source of truth carrying all context needed by every export path.
///
/// All callers (ExportSheet, buildPdfTable, buildPdfLedger, buildStyledExcelBytes,
/// buildPdfSellerReport, buildPdfMultiShopLedger) receive this object instead of
/// a bag of loose parameters. This guarantees:
///   • Locale + RTL flag are consistent across PDF, Excel, and image.
///   • User names are always resolved (never raw UIDs).
///   • Labels are always populated (never English fallbacks).
///   • Company branding (name, logo, currency) is uniform.
class ExportContext {
  /// Pre-resolved name map: uid → display name.
  final NameResolver names;

  /// Current app locale (en / ar / ur).
  final AppLocale locale;

  /// Company name from settings doc.
  final String companyName;

  /// ISO currency code or localized currency symbol.
  final String currency;

  /// Optional company logo bytes (base64-decoded from settings).
  final Uint8List? logoBytes;

  /// Fully-localized label map (all keys resolved via tr() before export).
  final Map<String, String> labels;

  const ExportContext({
    required this.names,
    required this.locale,
    required this.companyName,
    required this.currency,
    this.logoBytes,
    this.labels = const {},
  });

  /// Whether the locale is right-to-left.
  bool get isRtl => locale == AppLocale.ar || locale == AppLocale.ur;
}
