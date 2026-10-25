import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../l10n/app_locale.dart';
import '../l10n/financial_document_localization.dart';
import '../../models/transaction_model.dart';
import '../../models/invoice_model.dart';
import '../../models/settings_model.dart';

const _arabicShapingEnabled = bool.fromEnvironment(
  'use_arabic',
  defaultValue: false,
);

class PdfExportConfigurationException implements Exception {
  const PdfExportConfigurationException(this.code);

  final String code;

  @override
  String toString() => code;
}

/// Runs [computation] in an isolate on native platforms,
/// or inline on web (which doesn't support Isolate.run).
Future<R> _pdfCompute<R>(FutureOr<R> Function() computation) {
  if (kIsWeb) return Future.value(computation());
  return Isolate.run(computation);
}

/// Pre-loaded font bytes — loaded once on main isolate from rootBundle,
/// then sent into compute isolates as raw [Uint8List].
Uint8List? _arabicFontBytes;
Uint8List? _urduFontBytes;
Completer<void>? _fontBytesLoader;

/// Loads font byte data from assets (main-isolate only).
/// Must be called before any PDF export function.
Future<void> _ensureFontBytes() async {
  if (!_arabicShapingEnabled) {
    throw const PdfExportConfigurationException('pdf_arabic_shaping_disabled');
  }
  if (_arabicFontBytes != null && _urduFontBytes != null) return;
  if (_fontBytesLoader != null) {
    await _fontBytesLoader!.future;
    return;
  }

  final loader = Completer<void>();
  _fontBytesLoader = loader;
  try {
    final ad = await rootBundle.load('assets/fonts/NotoSansArabic.ttf');
    // Uint8List.fromList creates a copy with its own buffer (offset 0),
    // ensuring ByteData.view(bytes.buffer) in _fontsFromBytes works correctly
    // even when rootBundle returns a ByteData with non-zero offsetInBytes.
    _arabicFontBytes = Uint8List.fromList(
      ad.buffer.asUint8List(ad.offsetInBytes, ad.lengthInBytes),
    );
    final ud = await rootBundle.load('assets/fonts/NotoNastaliqUrdu.ttf');
    _urduFontBytes = Uint8List.fromList(
      ud.buffer.asUint8List(ud.offsetInBytes, ud.lengthInBytes),
    );
    loader.complete();
  } catch (error, stackTrace) {
    loader.completeError(error, stackTrace);
    rethrow;
  } finally {
    _fontBytesLoader = null;
  }
}

/// Recreates [pw.Font] objects from raw byte data (isolate-safe).
({pw.Font arabic, pw.Font urdu}) _fontsFromBytes(
  Uint8List arabicBytes,
  Uint8List urduBytes,
) {
  return (
    arabic: pw.Font.ttf(
      ByteData.view(
        arabicBytes.buffer,
        arabicBytes.offsetInBytes,
        arabicBytes.lengthInBytes,
      ),
    ),
    urdu: pw.Font.ttf(
      ByteData.view(
        urduBytes.buffer,
        urduBytes.offsetInBytes,
        urduBytes.lengthInBytes,
      ),
    ),
  );
}

pw.Document _buildDocument(pw.Font primaryFont, List<pw.Font> fontFallback) {
  return pw.Document(
    theme: pw.ThemeData.withFont(
      base: primaryFont,
      bold: primaryFont,
      italic: primaryFont,
      boldItalic: primaryFont,
      fontFallback: fontFallback,
    ),
  );
}

/// Sanitize user-provided text for PDF interpolation (S-08 hardening).
/// Strips control chars, collapses whitespace, trims.
String _s(String raw) => raw
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();

String _pdfExcerpt(String raw, {int maxRunes = 88}) {
  final runes = _s(raw).runes.toList(growable: false);
  if (runes.length <= maxRunes) return String.fromCharCodes(runes);
  return '${String.fromCharCodes(runes.take(maxRunes - 3))}...';
}

String _documentLabelWithSuffix(
  String key,
  String suffix,
  FinancialDocumentLanguagePair pair,
  AppLocale locale, {
  String separator = ': ',
}) => financialDocumentLabel(
  key,
  pair,
  fallback: trRead(key, locale),
).split('\n').map((line) => '$line$separator$suffix').join('\n');

pw.Widget _pairedLabelText(
  String text, {
  required pw.TextStyle style,
  pw.TextAlign align = pw.TextAlign.left,
}) {
  final lines = text.split('\n');
  final crossAxisAlignment = switch (align) {
    pw.TextAlign.center => pw.CrossAxisAlignment.center,
    pw.TextAlign.right => pw.CrossAxisAlignment.end,
    _ => pw.CrossAxisAlignment.start,
  };
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: crossAxisAlignment,
    children: [
      for (final (index, line) in lines.indexed)
        pw.Text(
          line,
          style: style,
          textAlign: align,
          textDirection: index == 0
              ? pw.TextDirection.ltr
              : pw.TextDirection.rtl,
        ),
    ],
  );
}

/// Returns true when [text] contains Arabic/Urdu script characters.
/// Used to auto-apply RTL direction to individual cells regardless of locale.
bool _containsRtlChars(String text) => RegExp(
  r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
).hasMatch(text);

/// Returns RTL direction when [text] contains RTL chars, otherwise [fallback].
pw.TextDirection _cellDir(String text, pw.TextDirection fallback) =>
    _containsRtlChars(text) ? pw.TextDirection.rtl : fallback;

const pw.TextDirection _amountDir = pw.TextDirection.ltr;

List<List<T>> paginateItems<T>(List<T> items, int itemsPerPage) {
  if (itemsPerPage <= 0) {
    throw ArgumentError.value(
      itemsPerPage,
      'itemsPerPage',
      'must be greater than zero',
    );
  }
  if (items.isEmpty) {
    return <List<T>>[<T>[]];
  }

  final pages = <List<T>>[];
  for (var index = 0; index < items.length; index += itemsPerPage) {
    final end = (index + itemsPerPage).clamp(0, items.length);
    pages.add(items.sublist(index, end));
  }
  return pages;
}

void _requireLabelKeys(
  Map<String, String> labels,
  Iterable<String> requiredKeys,
) {
  final missing = requiredKeys
      .where((key) => (labels[key] ?? '').trim().isEmpty)
      .toList();
  if (missing.isNotEmpty) {
    throw ArgumentError.value(
      labels,
      'labels',
      'Missing required PDF labels: ${missing.join(', ')}',
    );
  }
}

String _pdfLabel(Map<String, String> labels, String key, AppLocale locale) {
  final explicit = labels[key]?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final localized = trRead(key, locale);
  return localized == key ? '—' : localized;
}

String pdfCurrencyLabel(AppLocale locale, String currency) {
  final normalized = currency.trim().toUpperCase();
  if (locale == AppLocale.ar) {
    return switch (normalized) {
      'SAR' => 'ريال',
      'PKR' => 'روبية',
      _ => normalized,
    };
  }
  if (locale == AppLocale.ur) {
    return switch (normalized) {
      'SAR' => 'ریال',
      'PKR' => 'روپے',
      _ => normalized,
    };
  }
  return normalized;
}

/// Centralised locale → font/direction/currency configuration for all PDF
/// builders. Eliminates the previously 5× duplicated inline computation.
///
/// **Font policy:** NotoSansArabic is PRIMARY for ALL locales (including Urdu).
/// NotoNastaliqUrdu is kept as fallback only. The pdf package's TrueType
/// renderer cannot handle Nastaliq's complex GSUB/GPOS shaping tables —
/// using it as primary causes boxes and scattered characters.
class _PdfLocaleConfig {
  final AppLocale locale;
  final bool isRtl;
  final pw.TextDirection dir;
  final pw.CrossAxisAlignment align;
  final pw.Font primaryFont;
  final List<pw.Font> ff;
  final String currencyStr;

  _PdfLocaleConfig._({
    required this.locale,
    required this.isRtl,
    required this.dir,
    required this.align,
    required this.primaryFont,
    required this.ff,
    required this.currencyStr,
  });

  factory _PdfLocaleConfig({
    required ({pw.Font arabic, pw.Font urdu}) fonts,
    required AppLocale locale,
    String currency = 'SAR',
  }) {
    final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
    return _PdfLocaleConfig._(
      locale: locale,
      isRtl: isRtl,
      dir: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      align: isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      // NotoSansArabic covers full Arabic-script Unicode (including Urdu
      // characters) in Naskh style. Always primary for PDF rendering.
      primaryFont: fonts.arabic,
      ff: <pw.Font>[fonts.urdu],
      currencyStr: pdfCurrencyLabel(locale, currency),
    );
  }

  /// Shared text-style builder.
  pw.TextStyle ts({
    double size = 9,
    pw.FontWeight fw = pw.FontWeight.normal,
    PdfColor color = PdfColors.black,
  }) => pw.TextStyle(
    fontSize: size,
    fontWeight: fw,
    color: color,
    font: primaryFont,
    fontFallback: ff,
  );

  pw.Document buildDocument() => _buildDocument(primaryFont, ff);
}

double _headerTitleSize(String scale) => switch (scale) {
  'small' => 11,
  'large' => 16,
  _ => 13,
};

pw.Widget _workspaceBrandHeader({
  required InvoiceHeaderConfig header,
  required String fallbackName,
  required _PdfLocaleConfig localeConfig,
  Uint8List? logoBytes,
}) {
  final locale = localeConfig.locale;
  final pair = header.documentLanguagePair;
  final accent = _invoiceAccentColor(header.accentColor);
  final rtlName = pair == FinancialDocumentLanguagePair.englishArabic
      ? header.nameAr.trim()
      : header.nameUr.trim();
  final primaryName = header.nameEn.trim().isNotEmpty
      ? header.nameEn.trim()
      : fallbackName.trim();
  final otherNames = <(String, pw.TextDirection)>[
    if (rtlName.isNotEmpty && rtlName != primaryName)
      (rtlName, pw.TextDirection.rtl),
  ];
  final rtlSubtitle = pair == FinancialDocumentLanguagePair.englishArabic
      ? header.subtitleAr.trim()
      : header.subtitleUr.trim();
  final rtlAddress = pair == FinancialDocumentLanguagePair.englishArabic
      ? header.addressAr.trim()
      : header.addressUr.trim();
  final details = <(String, pw.TextDirection)>[];
  void addDetail(String key, String value) {
    final labels = financialDocumentLabel(
      key,
      pair,
      fallback: trRead(key, locale),
    ).split('\n');
    for (var index = 0; index < labels.length; index++) {
      details.add((
        '${labels[index]}: ${_s(value)}',
        index == 0 ? pw.TextDirection.ltr : pw.TextDirection.rtl,
      ));
    }
  }

  if (header.visibleFields.contains('phone') && header.phone.isNotEmpty) {
    addDetail('phone', header.phone);
  }
  if (header.visibleFields.contains('email') && header.email.isNotEmpty) {
    addDetail('email', header.email);
  }
  if (header.visibleFields.contains('tax_number') &&
      header.taxNumber.isNotEmpty) {
    addDetail('tax_registration_number', header.taxNumber);
  }
  if (header.visibleFields.contains('commercial_registration_number') &&
      header.commercialRegistrationNumber.isNotEmpty) {
    addDetail(
      'commercial_registration_number',
      header.commercialRegistrationNumber,
    );
  }
  final contentLines = <(String, pw.TextDirection)>[
    if (header.visibleFields.contains('subtitle') &&
        header.subtitleEn.trim().isNotEmpty)
      (header.subtitleEn.trim(), pw.TextDirection.ltr),
    if (header.visibleFields.contains('subtitle') && rtlSubtitle.isNotEmpty)
      (rtlSubtitle, pw.TextDirection.rtl),
    if (header.visibleFields.contains('address') &&
        header.addressEn.trim().isNotEmpty)
      (header.addressEn.trim(), pw.TextDirection.ltr),
    if (header.visibleFields.contains('address') && rtlAddress.isNotEmpty)
      (rtlAddress, pw.TextDirection.rtl),
  ];

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey50,
      border: pw.Border.all(color: accent, width: 1),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoBytes != null && header.visibleFields.contains('logo')) ...[
          pw.Image(
            pw.MemoryImage(logoBytes),
            height: 32,
            fit: pw.BoxFit.contain,
          ),
          pw.SizedBox(width: 8),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: localeConfig.align,
            children: [
              pw.Text(
                _s(primaryName),
                style: localeConfig.ts(
                  size: _headerTitleSize(header.titleScale),
                  fw: pw.FontWeight.bold,
                  color: accent,
                ),
                textDirection: pw.TextDirection.ltr,
                textAlign: pw.TextAlign.left,
              ),
              for (final (name, direction) in otherNames)
                pw.Text(
                  _s(name),
                  style: localeConfig.ts(size: 8, fw: pw.FontWeight.bold),
                  textDirection: direction,
                  textAlign: direction == pw.TextDirection.rtl
                      ? pw.TextAlign.right
                      : pw.TextAlign.left,
                ),
              for (final (line, direction) in contentLines)
                pw.Text(
                  _s(line),
                  style: localeConfig.ts(size: 8),
                  textDirection: direction,
                  textAlign: direction == pw.TextDirection.rtl
                      ? pw.TextAlign.right
                      : pw.TextAlign.left,
                ),
              for (final (detail, direction) in details)
                pw.Text(
                  detail,
                  style: localeConfig.ts(size: 7, color: PdfColors.grey700),
                  textDirection: direction,
                  textAlign: direction == pw.TextDirection.rtl
                      ? pw.TextAlign.right
                      : pw.TextAlign.left,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Builds a PDF document from tabular data and returns bytes.
/// When [locale] is Arabic or Urdu, loads the appropriate font and
/// renders all text RTL.
Future<Uint8List> buildPdfTable({
  required String title,
  required List<String> headers,
  required List<List<dynamic>> rows,
  String? subtitle,
  AppLocale locale = AppLocale.en,
  Uint8List? logoBytes,
  InvoiceHeaderConfig? header,
  String? companyName,
  String? pageLabel,
}) async {
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  return _pdfCompute(() {
    final fonts = _fontsFromBytes(aB, uB);
    final lc = _PdfLocaleConfig(fonts: fonts, locale: locale);
    final fontFallback = lc.ff;
    final dir = lc.dir;
    final isRtl = lc.isRtl;
    final pdf = lc.buildDocument();

    final headerStyle = lc.ts(size: 9, fw: pw.FontWeight.bold);
    final cellStyle = lc.ts(size: 8);
    final titleStyle = lc.ts(size: 16, fw: pw.FontWeight.bold);

    const rowsPerPage = 30;
    final pages = paginateItems(rows, rowsPerPage);
    final pageCount = pages.length;

    for (var page = 0; page < pageCount; page++) {
      final pageRows = pages[page];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: dir,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
            crossAxisAlignment: isRtl
                ? pw.CrossAxisAlignment.end
                : pw.CrossAxisAlignment.start,
            children: [
              if (page == 0) ...[
                if (header != null) ...[
                  _workspaceBrandHeader(
                    header: header,
                    fallbackName: companyName ?? 'My Business',
                    localeConfig: lc,
                    logoBytes: logoBytes,
                  ),
                  pw.SizedBox(height: 8),
                ] else if (logoBytes != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      height: 32,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.Text(
                  _s(title),
                  style: titleStyle,
                  textDirection: _cellDir(title, dir),
                ),
                if (subtitle != null)
                  pw.Text(
                    _s(subtitle),
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                      fontFallback: fontFallback,
                    ),
                    textDirection: dir,
                  ),
                pw.SizedBox(height: 12),
              ],
              pw.TableHelper.fromTextArray(
                context: context,
                headers: headers
                    .map(
                      (h) => pw.Text(
                        h,
                        style: headerStyle,
                        textDirection: _cellDir(h, dir),
                        textAlign: pw.TextAlign.center,
                      ),
                    )
                    .toList(),
                data: pageRows
                    .map(
                      (row) => row.map((c) => _s(c?.toString() ?? '')).toList(),
                    )
                    .toList(),
                headerStyle: headerStyle,
                cellStyle: cellStyle,
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blue800,
                ),
                cellHeight: 22,
                headerDirection: dir,
                tableDirection: dir,
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                oddRowDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey50,
                ),
                cellAlignments: {
                  for (var i = 0; i < headers.length; i++)
                    i: pw.Alignment.center,
                },
                cellBuilder: (colIdx, data, rowNum) {
                  final text = data?.toString() ?? '';
                  return pw.Text(
                    text,
                    style: cellStyle,
                    textDirection: _cellDir(text, dir),
                    textAlign: pw.TextAlign.center,
                  );
                },
              ),
              pw.Spacer(),
              pw.Align(
                alignment: isRtl
                    ? pw.Alignment.centerLeft
                    : pw.Alignment.centerRight,
                child: pw.Text(
                  (pageLabel ?? trRead('page_x_of_y', locale))
                      .replaceAll('%1', '${page + 1}')
                      .replaceAll('%2', '$pageCount'),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }); // Isolate.run
}

// ─────────────────────────────────────────────────────────────────────────────
// CA-grade Account Statement (portrait A4, running balance)
// ─────────────────────────────────────────────────────────────────────────────

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

PdfColor _invoiceAccentColor(String value) => switch (value.toUpperCase()) {
  '#1F4E79' => PdfColors.blue800,
  '#315C4C' => PdfColors.green800,
  '#8A3A3A' => PdfColors.red800,
  '#222222' => PdfColors.grey900,
  _ => PdfColors.black,
};

String _fmtAmt(double v) => v.toStringAsFixed(2);
String _fmtAmtC(double v, String currency) => currency.isEmpty
    ? v.toStringAsFixed(2)
    : '${v.toStringAsFixed(2)} $currency';

InvoiceHeaderConfig resolveInvoiceHeaderForPrint({
  required InvoiceModel invoice,
  InvoiceHeaderConfig? currentHeader,
}) {
  if (currentHeader != null) return currentHeader;
  if (invoice.headerSnapshot.isNotEmpty) {
    return InvoiceHeaderConfig.fromJson(invoice.headerSnapshot);
  }
  return const InvoiceHeaderConfig();
}

class LedgerSummary {
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;

  const LedgerSummary({
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
  });
}

LedgerSummary calculateLedgerSummary({
  required double openingBalance,
  required Iterable<TransactionModel> transactions,
}) {
  var balance = openingBalance;
  var totalDebit = 0.0;
  var totalCredit = 0.0;
  for (final transaction in transactions) {
    final impact = transaction.balanceImpact;
    balance += impact;
    if (impact > 0) {
      totalDebit += impact;
    } else if (impact < 0) {
      totalCredit -= impact;
    }
  }
  return LedgerSummary(
    totalDebit: totalDebit,
    totalCredit: totalCredit,
    closingBalance: balance,
  );
}

/// Builds a CA-grade customer account statement PDF with running balance,
/// summary totals, and optional Entry By column.
///
/// [companyName] and [generatedBy] populate the report header.
/// [entryByMap] maps uid → display name for the Entry By column.
Future<Uint8List> buildPdfLedger({
  required String shopName,
  required String companyName,
  String generatedBy = '',
  DateTime? dateFrom,
  DateTime? dateTo,
  required double openingBalance,
  required List<TransactionModel> transactions,
  Map<String, String> entryByMap = const {},
  bool showEntryBy = false,
  required Map<String, String> labels,
  AppLocale locale = AppLocale.en,
  String currency = 'SAR',
  Uint8List? logoBytes,
  InvoiceHeaderConfig? header,
}) async {
  _requireLabelKeys(labels, const <String>[
    'account_statement',
    'report_date',
    'generated_by',
    'date',
    'description',
    'debit',
    'credit',
    'running_balance',
    'net_payable',
    'total_entries',
    'page',
    'opening_balance',
  ]);
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  return _pdfCompute(() {
    final fonts = _fontsFromBytes(aB, uB);
    final lc = _PdfLocaleConfig(
      fonts: fonts,
      locale: locale,
      currency: currency,
    );
    final dir = lc.dir;
    final align = lc.align;
    final primaryFont = lc.primaryFont;
    final ff = lc.ff;
    final currencyStr = lc.currencyStr;
    pw.TextStyle ts({
      double size = 9,
      pw.FontWeight fw = pw.FontWeight.normal,
      PdfColor color = PdfColors.black,
    }) => lc.ts(size: size, fw: fw, color: color);

    // ── build ledger rows ──
    final summary = calculateLedgerSummary(
      openingBalance: openingBalance,
      transactions: transactions,
    );
    var balance = openingBalance;
    final int entryCount = transactions.length;

    final rows = <_LedgerRow>[];
    // Insert an opening-balance row so the final running balance is
    // always reconcilable to the stored account balance.
    if (openingBalance != 0) {
      rows.add(
        _LedgerRow(
          date: '',
          desc: _pdfLabel(labels, 'opening_balance', locale),
          entryBy: '',
          mode: '',
          cashIn: 0,
          cashOut: 0,
          balance: openingBalance,
        ),
      );
    }
    for (final tx in transactions) {
      final date = tx.createdAt.toDate();
      final rawDesc = tx.description?.isNotEmpty == true
          ? _s(tx.description!)
          : (tx.hasItems
                ? tx.items.map((i) => _s(i.productName)).join(', ')
                : '');
      // Prepend invoice number for cross-reference when available
      final desc = tx.invoiceNumber != null && tx.invoiceNumber!.isNotEmpty
          ? '[${_s(tx.invoiceNumber!)}] $rawDesc'
          : rawDesc;
      final mode = tx.saleType ?? '';
      final entryBy = showEntryBy ? (entryByMap[tx.createdBy] ?? '—') : '';

      final impact = tx.balanceImpact;
      balance += impact;
      rows.add(
        _LedgerRow(
          date: _fmtDate(date),
          desc: desc,
          entryBy: entryBy,
          mode: mode,
          cashIn: impact < 0 ? -impact : 0,
          cashOut: impact > 0 ? impact : 0,
          balance: balance,
        ),
      );
    }

    // ── column widths (portrait A4 usable ≈ 539 pt) ──
    // A4 portrait usable width ≈ 539 pt (595 − 28 − 28 margins)
    const double dateW = 54;
    const double entryByW = 68;
    const double amtW = 72;
    const double balW = 76;
    // Remark column fills remaining width so rows always span the full page.
    const double usable = 539;
    final double remarkW = showEntryBy
        ? usable -
              dateW -
              entryByW -
              amtW -
              amtW -
              balW // 197
        : usable - dateW - amtW - amtW - balW; // 265

    final colWidths = showEntryBy
        ? [dateW, remarkW, entryByW, amtW, amtW, balW]
        : [dateW, remarkW, amtW, amtW, balW];
    final headerLabels = showEntryBy
        ? [
            _pdfLabel(labels, 'date', locale),
            _pdfLabel(labels, 'description', locale),
            _pdfLabel(labels, 'entry_by', locale),
            _pdfLabel(labels, 'debit', locale),
            _pdfLabel(labels, 'credit', locale),
            _pdfLabel(labels, 'running_balance', locale),
          ]
        : [
            _pdfLabel(labels, 'date', locale),
            _pdfLabel(labels, 'description', locale),
            _pdfLabel(labels, 'debit', locale),
            _pdfLabel(labels, 'credit', locale),
            _pdfLabel(labels, 'running_balance', locale),
          ];
    final colCount = colWidths.length;

    final pdf = _buildDocument(primaryFont, ff);
    final now = DateTime.now();

    // NOTE (RR-017): Use pw.MultiPage so the PDF renderer measures and
    // flows content naturally across pages. This prevents the fixed-row
    // manual pagination from overflowing the final page when extra
    // summary blocks are appended (which historically clipped the newest
    // transactions because rows are oldest→newest).
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        textDirection: dir,
        header: (ctx) {
          if (ctx.pageNumber == 1) {
            return pw.Column(
              crossAxisAlignment: align,
              children: [
                _workspaceBrandHeader(
                  header: header ?? const InvoiceHeaderConfig(),
                  fallbackName: companyName,
                  localeConfig: lc,
                  logoBytes: logoBytes,
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _pairedLabelText(
                      _pdfLabel(labels, 'account_statement', locale),
                      style: ts(
                        size: 11,
                        fw: pw.FontWeight.bold,
                        color: _invoiceAccentColor(
                          header?.accentColor ?? '#315C4C',
                        ),
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _pairedLabelText(
                          '${_pdfLabel(labels, 'report_date', locale)}: ${_fmtDate(now)}',
                          style: ts(size: 8, color: PdfColors.grey700),
                        ),
                        if (generatedBy.isNotEmpty)
                          _pairedLabelText(
                            '${_pdfLabel(labels, 'generated_by', locale)}: ${_s(generatedBy)}',
                            style: ts(size: 8, color: PdfColors.grey700),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1.5, color: PdfColors.blue800),
                pw.SizedBox(height: 6),
                pw.Text(
                  _s(shopName),
                  style: ts(size: 14, fw: pw.FontWeight.bold),
                  textDirection: _cellDir(shopName, dir),
                ),
                pw.SizedBox(height: 4),
                if (dateFrom != null && dateTo != null)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                    ),
                    child: _pairedLabelText(
                      '${_pdfLabel(labels, 'duration', locale)}: ${_fmtDate(dateFrom)} — ${_fmtDate(dateTo)}',
                      style: ts(size: 8, color: PdfColors.grey700),
                    ),
                  ),
                pw.SizedBox(height: 8),
                // Summary 3-column
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue100, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    children: [
                      _summaryCell(
                        label: _pdfLabel(labels, 'credit', locale),
                        value: _fmtAmtC(summary.totalCredit, currencyStr),
                        color: PdfColors.green800,
                        primaryFont: primaryFont,
                        direction: dir,
                        ff: ff,
                      ),
                      pw.Container(
                        width: 0.5,
                        height: 40,
                        color: PdfColors.blue100,
                      ),
                      _summaryCell(
                        label: _pdfLabel(labels, 'debit', locale),
                        value: _fmtAmtC(summary.totalDebit, currencyStr),
                        color: PdfColors.red800,
                        primaryFont: primaryFont,
                        direction: dir,
                        ff: ff,
                      ),
                      pw.Container(
                        width: 0.5,
                        height: 40,
                        color: PdfColors.blue100,
                      ),
                      _summaryCell(
                        label: _pdfLabel(labels, 'net_payable', locale),
                        value: _fmtAmtC(
                          summary.closingBalance.abs(),
                          currencyStr,
                        ),
                        color: balance > 0
                            ? PdfColors.red800
                            : PdfColors.green800,
                        primaryFont: primaryFont,
                        direction: dir,
                        ff: ff,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),
                _pairedLabelText(
                  '${_pdfLabel(labels, 'total_entries', locale)}: $entryCount',
                  style: ts(size: 8, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 8),
                _buildLedgerHeaderRow(
                  headerLabels,
                  colWidths,
                  colCount,
                  dir,
                  primaryFont,
                  ff,
                ),
              ],
            );
          }
          return _buildLedgerHeaderRow(
            headerLabels,
            colWidths,
            colCount,
            dir,
            primaryFont,
            ff,
          );
        },
        footer: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: _pairedLabelText(
                '${_pdfLabel(labels, 'page', locale)} ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: ts(size: 7, color: PdfColors.grey500),
              ),
            ),
          ],
        ),
        build: (ctx) => [
          // data rows
          ...rows.asMap().entries.map((e) {
            final idx = e.key;
            final r = e.value;
            final bg = idx % 2 == 0 ? PdfColors.white : PdfColors.grey50;
            return _buildLedgerDataRow(
              r,
              colWidths,
              colCount,
              bg,
              dir,
              primaryFont,
              ff,
              showEntryBy,
              currencyStr,
            );
          }),

          // final balance as last flow item — MultiPage will place it where it fits
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                right: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: colWidths
                      .take(colCount - 1)
                      .fold<double>(0, (a, b) => a + b),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(
                        color: PdfColors.grey400,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: pw.Text(
                    _pdfLabel(labels, 'net_payable', locale),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                      font: primaryFont,
                      fontFallback: ff,
                    ),
                    textDirection: dir,
                  ),
                ),
                pw.Container(
                  width: colWidths.last,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  child: pw.Text(
                    _fmtAmtC(summary.closingBalance, currencyStr),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: balance > 0
                          ? PdfColors.red800
                          : PdfColors.green800,
                      font: primaryFont,
                      fontFallback: ff,
                    ),
                    textDirection: _amountDir,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }); // Isolate.run
}

class _LedgerRow {
  final String date;
  final String desc;
  final String entryBy;
  final String mode;
  final double cashIn;
  final double cashOut;
  final double balance;
  const _LedgerRow({
    required this.date,
    required this.desc,
    required this.entryBy,
    required this.mode,
    required this.cashIn,
    required this.cashOut,
    required this.balance,
  });
}

pw.Widget _summaryCell({
  required String label,
  required String value,
  required PdfColor color,
  required pw.Font primaryFont,
  required pw.TextDirection direction,
  required List<pw.Font> ff,
  bool isBold = false,
}) {
  return pw.Expanded(
    child: pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _pairedLabelText(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey600,
              font: primaryFont,
              fontFallback: ff,
            ),
            align: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
              font: primaryFont,
              fontFallback: ff,
            ),
            textAlign: pw.TextAlign.center,
            textDirection: _amountDir,
          ),
        ],
      ),
    ),
  );
}

pw.Widget _buildLedgerHeaderRow(
  List<String> labels,
  List<double> widths,
  int count,
  pw.TextDirection dir,
  pw.Font primaryFont,
  List<pw.Font> ff,
) {
  return pw.Container(
    decoration: const pw.BoxDecoration(
      color: PdfColors.blue800,
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
    ),
    child: pw.Row(
      children: List.generate(count, (i) {
        return pw.Container(
          width: widths[i],
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: i == 0
                  ? const pw.BorderSide(color: PdfColors.grey400, width: 0.5)
                  : pw.BorderSide.none,
              right: const pw.BorderSide(color: PdfColors.blue300, width: 0.5),
            ),
          ),
          child: _pairedLabelText(
            labels[i],
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              font: primaryFont,
              fontFallback: ff,
            ),
            align: pw.TextAlign.center,
          ),
        );
      }),
    ),
  );
}

pw.Widget _buildLedgerDataRow(
  _LedgerRow r,
  List<double> widths,
  int count,
  PdfColor bg,
  pw.TextDirection dir,
  pw.Font primaryFont,
  List<pw.Font> ff,
  bool showEntryBy,
  String currencyStr,
) {
  final cells = showEntryBy
      ? [
          r.date,
          r.desc,
          r.entryBy,
          r.cashOut > 0 ? _fmtAmtC(r.cashOut, currencyStr) : '',
          r.cashIn > 0 ? _fmtAmtC(r.cashIn, currencyStr) : '',
          _fmtAmtC(r.balance, currencyStr),
        ]
      : [
          r.date,
          r.desc,
          r.cashOut > 0 ? _fmtAmtC(r.cashOut, currencyStr) : '',
          r.cashIn > 0 ? _fmtAmtC(r.cashIn, currencyStr) : '',
          _fmtAmtC(r.balance, currencyStr),
        ];
  final cashOutIdx = showEntryBy ? 3 : 2;
  final cashInIdx = showEntryBy ? 4 : 3;

  return pw.Container(
    decoration: pw.BoxDecoration(
      color: bg,
      border: const pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    ),
    child: pw.Row(
      children: List.generate(count, (i) {
        PdfColor? color;
        if (i == cashInIdx && r.cashIn > 0) color = PdfColors.green800;
        if (i == cashOutIdx && r.cashOut > 0) color = PdfColors.red800;
        return pw.Container(
          width: widths[i],
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: i == 0
                  ? const pw.BorderSide(color: PdfColors.grey300, width: 0.5)
                  : pw.BorderSide.none,
              right: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Text(
            cells[i],
            style: pw.TextStyle(
              fontSize: 8,
              color: color,
              font: primaryFont,
              fontFallback: ff,
            ),
            textAlign: pw.TextAlign.center,
            textDirection: i >= cashOutIdx
                ? _amountDir
                : _cellDir(cells[i], dir),
          ),
        );
      }),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Seller Summary Report (portrait A4)
// ─────────────────────────────────────────────────────────────────────────────

/// A single customer row inside the seller report.
class SellerReportShop {
  final String name;
  final int totalPairsSold;
  final double totalRevenue;
  final double outstandingBalance;
  final String currency;

  const SellerReportShop({
    required this.name,
    required this.totalPairsSold,
    required this.totalRevenue,
    required this.outstandingBalance,
    this.currency = 'SAR',
  });
}

typedef SellerReportCurrencyTotals = ({double revenue, double outstanding});

Map<String, SellerReportCurrencyTotals> sellerReportTotalsByCurrency(
  List<SellerReportShop> shops,
) {
  final totals = <String, SellerReportCurrencyTotals>{};
  for (final shop in shops) {
    final normalizedCurrency = shop.currency.trim().toUpperCase();
    final currency = normalizedCurrency.isEmpty ? 'SAR' : normalizedCurrency;
    final current = totals[currency] ?? (revenue: 0.0, outstanding: 0.0);
    totals[currency] = (
      revenue: current.revenue + shop.totalRevenue,
      outstanding: current.outstanding + shop.outstandingBalance,
    );
  }
  return totals;
}

/// Builds a seller summary report PDF.
///
/// [sellerName], [sellerPhone], [routeName] describe the seller.
/// [shops] is the list of summarised shop rows.
/// [stockReceived], [stockSold], [stockRemaining] are in pairs.
Future<Uint8List> buildPdfSellerReport({
  required String sellerName,
  required String sellerPhone,
  required String routeName,
  required List<SellerReportShop> shops,
  required int stockReceived,
  required int stockSold,
  required int stockRemaining,
  required Map<String, String> labels,
  AppLocale locale = AppLocale.en,
  Uint8List? logoBytes,
  InvoiceHeaderConfig? header,
  String companyName =
      'FOOTWEAR', // ISSUE-015: was hardcoded; now parameterised
}) async {
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  return _pdfCompute(() {
    final fonts = _fontsFromBytes(aB, uB);
    final lc = _PdfLocaleConfig(fonts: fonts, locale: locale);
    final isRtl = lc.isRtl;
    final dir = lc.dir;
    final primaryFont = lc.primaryFont;
    final ff = lc.ff;
    pw.TextStyle ts({
      double size = 9,
      pw.FontWeight fw = pw.FontWeight.normal,
      PdfColor color = PdfColors.black,
    }) => lc.ts(size: size, fw: fw, color: color);

    final currencyTotals = sellerReportTotalsByCurrency(shops);
    int totalPairs = 0;
    for (final c in shops) {
      totalPairs += c.totalPairsSold;
    }

    final pdf = lc.buildDocument();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        textDirection: dir,
        build: (ctx) => [
          _workspaceBrandHeader(
            header: header ?? const InvoiceHeaderConfig(),
            fallbackName: companyName,
            localeConfig: lc,
            logoBytes: logoBytes,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _pdfLabel(labels, 'seller_report', locale),
                style: ts(
                  size: 13,
                  fw: pw.FontWeight.bold,
                  color: _invoiceAccentColor(header?.accentColor ?? '#315C4C'),
                ),
                textDirection: dir,
              ),
              pw.Text(
                '${_pdfLabel(labels, 'report_date', locale)}: ${_fmtDate(DateTime.now())}',
                style: ts(size: 8, color: PdfColors.grey700),
                textDirection: dir,
              ),
            ],
          ),
          pw.Divider(thickness: 1.5, color: PdfColors.blue800),
          pw.SizedBox(height: 6),

          // ── Seller Info ──
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${_pdfLabel(labels, 'seller', locale)}: ${_s(sellerName)}',
                      style: ts(size: 10, fw: pw.FontWeight.bold),
                      textDirection: _cellDir(sellerName, dir),
                    ),
                    pw.Text(
                      _s(sellerPhone),
                      style: ts(size: 9),
                      textDirection: dir,
                    ),
                  ],
                ),
                pw.Text(
                  '${_pdfLabel(labels, 'route', locale)}: ${_s(routeName)}',
                  style: ts(size: 10, fw: pw.FontWeight.bold),
                  textDirection: _cellDir(routeName, dir),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // ── Stock Summary ──
          pw.Text(
            _pdfLabel(labels, 'inventory', locale),
            style: ts(size: 11, fw: pw.FontWeight.bold),
            textDirection: dir,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              _stockCard(
                _pdfLabel(labels, 'stock_received', locale),
                stockReceived.toString(),
                PdfColors.blue50,
                primaryFont: primaryFont,
                ff: ff,
              ),
              pw.SizedBox(width: 8),
              _stockCard(
                _pdfLabel(labels, 'stock_sold', locale),
                stockSold.toString(),
                PdfColors.orange50,
                primaryFont: primaryFont,
                ff: ff,
              ),
              pw.SizedBox(width: 8),
              _stockCard(
                _pdfLabel(labels, 'stock_remaining', locale),
                stockRemaining.toString(),
                PdfColors.green50,
                primaryFont: primaryFont,
                ff: ff,
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ── Customer Table ──
          pw.Text(
            _pdfLabel(labels, 'shops', locale),
            style: ts(size: 11, fw: pw.FontWeight.bold),
            textDirection: dir,
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers:
                [
                      _pdfLabel(labels, 'shop', locale),
                      _pdfLabel(labels, 'stock_sold', locale),
                      _pdfLabel(labels, 'revenue', locale),
                      _pdfLabel(labels, 'outstanding', locale),
                    ]
                    .map(
                      (h) => pw.Text(
                        h,
                        style: lc.ts(
                          size: 8,
                          fw: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                        textDirection: _cellDir(h, dir),
                        textAlign: pw.TextAlign.center,
                      ),
                    )
                    .toList(),
            data: shops
                .map(
                  (c) => [
                    _s(c.name),
                    c.totalPairsSold.toString(),
                    _fmtAmtC(
                      c.totalRevenue,
                      pdfCurrencyLabel(locale, c.currency),
                    ),
                    _fmtAmtC(
                      c.outstandingBalance,
                      pdfCurrencyLabel(locale, c.currency),
                    ),
                  ],
                )
                .toList(),
            headerStyle: lc.ts(
              size: 8,
              fw: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            cellStyle: lc.ts(size: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
            cellHeight: 22,
            headerDirection: dir,
            tableDirection: dir,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            cellAlignments: {
              for (var i = 0; i < 4; i++) i: pw.Alignment.center,
            },
            cellBuilder: (colIdx, data, rowNum) {
              final text = data?.toString() ?? '';
              return pw.Text(
                text,
                style: lc.ts(size: 8),
                textDirection: colIdx >= 1 ? _amountDir : _cellDir(text, dir),
                textAlign: pw.TextAlign.center,
              );
            },
          ),
          pw.SizedBox(height: 8),

          // ── Grand Totals ──
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue200, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: isRtl
                  ? pw.CrossAxisAlignment.end
                  : pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${_pdfLabel(labels, 'total', locale)} ${_pdfLabel(labels, 'stock_sold', locale)}: $totalPairs ${_pdfLabel(labels, 'pairs', locale)}',
                  style: ts(size: 9, fw: pw.FontWeight.bold),
                  textDirection: dir,
                ),
                ...currencyTotals.entries.map((entry) {
                  final currencyLabel = pdfCurrencyLabel(locale, entry.key);
                  final outstandingColor = entry.value.outstanding > 0
                      ? PdfColors.red700
                      : PdfColors.green700;
                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '$currencyLabel ${_pdfLabel(labels, 'revenue', locale)}: ${_fmtAmt(entry.value.revenue)}',
                        style: ts(size: 9, fw: pw.FontWeight.bold),
                        textDirection: dir,
                      ),
                      pw.Text(
                        '$currencyLabel ${_pdfLabel(labels, 'outstanding', locale)}: ${_fmtAmt(entry.value.outstanding)}',
                        style: ts(
                          size: 9,
                          fw: pw.FontWeight.bold,
                          color: outstandingColor,
                        ),
                        textDirection: dir,
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }); // Isolate.run
}

pw.Widget _stockCard(
  String label,
  String value,
  PdfColor bg, {
  required pw.Font primaryFont,
  required List<pw.Font> ff,
}) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              font: primaryFont,
              fontFallback: ff,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey700,
              font: primaryFont,
              fontFallback: ff,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Invoice PDF (portrait A4)
// ─────────────────────────────────────────────────────────────────────────────

/// Generates a single-page invoice PDF (sale or credit note).
Future<Uint8List> generateInvoicePdf({
  required InvoiceModel invoice,
  required String companyName,
  String currency = 'SAR',
  AppLocale locale = AppLocale.en,
  Uint8List? logoBytes,
  InvoiceHeaderConfig? header,
}) async {
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  final headerConfig = resolveInvoiceHeaderForPrint(
    invoice: invoice,
    currentHeader: header,
  );
  final savedCompanyName =
      (invoice.headerSnapshot['company_name'] as String?)?.trim() ?? '';
  final displayCompanyName = headerConfig.nameEn.trim().isNotEmpty
      ? headerConfig.nameEn.trim()
      : header != null && companyName.trim().isNotEmpty
      ? companyName.trim()
      : savedCompanyName.isNotEmpty
      ? savedCompanyName
      : companyName;
  var effectiveLogoBytes = logoBytes;
  if (header == null && invoice.headerSnapshot.isNotEmpty) {
    final savedLogo = invoice.headerSnapshot['logo_base64'] as String?;
    try {
      effectiveLogoBytes = savedLogo == null ? null : base64Decode(savedLogo);
    } catch (_) {
      effectiveLogoBytes = null;
    }
  }
  final accentColor = _invoiceAccentColor(headerConfig.accentColor);
  String label(String key) => financialDocumentLabel(
    key,
    headerConfig.documentLanguagePair,
    fallback: trRead(key, locale),
  );
  final lblSubtotal = label('subtotal');
  final lblDiscount = label('discount');
  final lblNotes = label('notes');
  final lblInvoiceTitle = label('invoice_title');
  final lblCreditNote = label('credit_note');
  final lblItem = label('item_number');
  final lblSize = label('size');
  final lblColor = label('color');
  final lblQty = label('qty');
  final lblUnitPrice = label('unit_price');
  final lblTotal = label('total');
  final lblVoid = label('void');
  final lblReceipt = label('cash_receipt');
  final lblAmountReceived = label('amount_received');
  final lblSignature = label('signature');
  final paymentMethodLabel = switch (invoice.paymentMethod) {
    'cash' => label('payment_method_cash'),
    'bank_transfer' => label('payment_method_bank_transfer'),
    'cheque' => label('payment_method_cheque'),
    _ => null,
  };
  return _pdfCompute(() {
    final fonts = _fontsFromBytes(aB, uB);
    final lc = _PdfLocaleConfig(
      fonts: fonts,
      locale: locale,
      currency: currency,
    );
    final dir = lc.dir;
    final align = lc.align;
    final primaryFont = lc.primaryFont;
    final ff = lc.ff;
    pw.TextStyle ts({
      double size = 9,
      pw.FontWeight fw = pw.FontWeight.normal,
      PdfColor color = PdfColors.black,
    }) => lc.ts(size: size, fw: fw, color: color);
    final currencyLabel = lc.currencyStr;
    final pair = headerConfig.documentLanguagePair;
    pw.Widget pairedLabel(
      String text, {
      required pw.TextStyle style,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      final lines = text.split('\n');
      final crossAxisAlignment = switch (align) {
        pw.TextAlign.center => pw.CrossAxisAlignment.center,
        pw.TextAlign.right => pw.CrossAxisAlignment.end,
        _ => pw.CrossAxisAlignment.start,
      };
      return pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          for (final (index, line) in lines.indexed)
            pw.Text(
              line,
              style: style,
              textAlign: align,
              textDirection: index == 0
                  ? pw.TextDirection.ltr
                  : pw.TextDirection.rtl,
            ),
        ],
      );
    }

    final date = invoice.createdAt.toDate();
    final dateStr = _fmtDate(date);
    final isCashReceipt = invoice.isCashReceipt;
    final isCreditNote = invoice.isCreditNote || invoice.isReturn;
    final docTitle = isCashReceipt
        ? lblReceipt
        : isCreditNote
        ? lblCreditNote
        : invoice.isNonStockSale
        ? label('invoice_non_stock_mode')
        : lblInvoiceTitle;
    final printAt = DateTime.now();
    final printDateTime =
        '${_fmtDate(printAt)} ${printAt.hour.toString().padLeft(2, '0')}:${printAt.minute.toString().padLeft(2, '0')}';

    final pdf = _buildDocument(primaryFont, ff);

    if (isCashReceipt) {
      final receiptHeader = headerConfig.copyWith(
        template: 'compact',
        titleScale: 'small',
        visibleFields: headerConfig.visibleFields.intersection({
          'logo',
          'phone',
          'email',
        }),
      );
      final receiptRows = <(String, String)>[
        ('received_from', invoice.shopName),
        ('date', dateStr),
        if (invoice.cashReceiptSequence != null)
          ('receipt_sequence', invoice.cashReceiptSequence.toString()),
        if (invoice.sellerName.trim().isNotEmpty)
          ('received_by', invoice.sellerName),
        if (paymentMethodLabel != null) ('payment_method', paymentMethodLabel),
        if (invoice.paymentReference?.trim().isNotEmpty == true)
          ('payment_reference', invoice.paymentReference!),
        if (invoice.linkedInvoiceId?.trim().isNotEmpty == true)
          ('linked_invoice', invoice.linkedInvoiceId!),
      ];
      final printLabel = _documentLabelWithSuffix(
        'print_date',
        printDateTime,
        pair,
        locale,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          textDirection: dir,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _workspaceBrandHeader(
                header: receiptHeader,
                fallbackName: displayCompanyName,
                localeConfig: lc,
                logoBytes: effectiveLogoBytes,
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pairedLabel(
                            docTitle,
                            style: ts(
                              size: 10,
                              fw: pw.FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                          pw.Text(
                            _pdfExcerpt(invoice.invoiceNumber, maxRunes: 48),
                            style: ts(size: 11, fw: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    pairedLabel(
                      _documentLabelWithSuffix('date', dateStr, pair, locale),
                      style: ts(size: 8, color: PdfColors.grey700),
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  border: pw.Border.all(color: accentColor, width: 1),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  children: [
                    pairedLabel(
                      lblAmountReceived,
                      style: ts(size: 8, color: PdfColors.grey700),
                      align: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 3),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          currencyLabel,
                          style: ts(size: 10, fw: pw.FontWeight.bold),
                          textDirection: _cellDir(currencyLabel, dir),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Text(
                          _fmtAmt(invoice.total),
                          style: ts(
                            size: 22,
                            fw: pw.FontWeight.bold,
                            color: accentColor,
                          ),
                          textDirection: _amountDir,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(3),
                },
                children: [
                  for (final (index, row) in receiptRows.indexed)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: index.isEven
                            ? PdfColors.white
                            : PdfColors.grey50,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 5,
                          ),
                          child: pairedLabel(
                            label(row.$1),
                            style: ts(size: 7, fw: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 5,
                          ),
                          child: pw.Text(
                            _pdfExcerpt(row.$2),
                            style: ts(size: 8),
                            maxLines: 2,
                            textDirection: _cellDir(row.$2, dir),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              pw.Spacer(),
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: align,
                      children: [
                        pairedLabel(
                          _documentLabelWithSuffix(
                            'received_by',
                            _pdfExcerpt(invoice.sellerName, maxRunes: 48),
                            pair,
                            locale,
                          ),
                          style: ts(size: 8, fw: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 22),
                        pw.Divider(color: PdfColors.grey500, thickness: 0.5),
                        pairedLabel(
                          lblSignature,
                          style: ts(size: 7, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 24),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: align,
                      children: [
                        pw.SizedBox(height: 12),
                        pw.SizedBox(height: 22),
                        pw.Divider(color: PdfColors.grey500, thickness: 0.5),
                        pairedLabel(
                          _documentLabelWithSuffix(
                            'received_from',
                            _pdfExcerpt(invoice.shopName, maxRunes: 48),
                            pair,
                            locale,
                          ),
                          style: ts(size: 7, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${_pdfExcerpt(displayCompanyName, maxRunes: 48)} • $dateStr',
                    style: ts(size: 7, color: PdfColors.grey500),
                    textDirection: _cellDir(displayCompanyName, dir),
                  ),
                  pairedLabel(
                    printLabel,
                    style: ts(size: 7, color: PdfColors.grey600),
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      return pdf.save();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        textDirection: dir,
        footer: (ctx) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_s(displayCompanyName)} • $dateStr',
                  style: ts(size: 7, color: PdfColors.grey500),
                  textDirection: _cellDir(displayCompanyName, dir),
                ),
                pairedLabel(
                  _documentLabelWithSuffix(
                    'print_date',
                    '$printDateTime  |  ${label('page_x_of_y').replaceAll('%1', '${ctx.pageNumber}').replaceAll('%2', '${ctx.pagesCount}')}',
                    pair,
                    locale,
                  ),
                  style: ts(size: 7, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          _workspaceBrandHeader(
            header: headerConfig,
            fallbackName: displayCompanyName,
            localeConfig: lc,
            logoBytes: effectiveLogoBytes,
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pairedLabel(
                        docTitle,
                        style: ts(
                          size: 10,
                          fw: pw.FontWeight.bold,
                          color: isCreditNote
                              ? PdfColors.green800
                              : accentColor,
                        ),
                      ),
                      pw.Text(
                        _s(invoice.invoiceNumber),
                        style: ts(size: 10, fw: pw.FontWeight.bold),
                        textDirection: dir,
                      ),
                    ],
                  ),
                ),
                pairedLabel(
                  _documentLabelWithSuffix('date', dateStr, pair, locale),
                  style: ts(size: 8, color: PdfColors.grey700),
                  align: pw.TextAlign.right,
                ),
                if (invoice.status == 'void')
                  pairedLabel(
                    lblVoid,
                    style: ts(
                      size: 10,
                      fw: pw.FontWeight.bold,
                      color: PdfColors.red,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // Customer or receipt payer details.
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: align,
              children: [
                pairedLabel(
                  _documentLabelWithSuffix(
                    'shop',
                    _s(invoice.shopName),
                    pair,
                    locale,
                  ),
                  style: ts(size: 10, fw: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Items table
          if (invoice.items.isNotEmpty)
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: invoice.isNonStockSale
                  ? {
                      0: const pw.FlexColumnWidth(4),
                      1: const pw.FlexColumnWidth(1),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FlexColumnWidth(2),
                    }
                  : {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(1.5),
                      2: const pw.FlexColumnWidth(1.5),
                      3: const pw.FlexColumnWidth(1),
                      4: const pw.FlexColumnWidth(2),
                      5: const pw.FlexColumnWidth(2),
                    },
              children: [
                // header row
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: accentColor),
                  children:
                      (invoice.isNonStockSale
                              ? [lblItem, lblQty, lblUnitPrice, lblTotal]
                              : [
                                  lblItem,
                                  lblSize,
                                  lblColor,
                                  lblQty,
                                  lblUnitPrice,
                                  lblTotal,
                                ])
                          .map(
                            (h) => pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 5,
                              ),
                              child: pairedLabel(
                                h,
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white,
                                  font: primaryFont,
                                  fontFallback: ff,
                                ),
                                align: pw.TextAlign.center,
                              ),
                            ),
                          )
                          .toList(),
                ),
                // data rows
                ...invoice.items.asMap().entries.map((e) {
                  final i = e.key;
                  final item = e.value;
                  final bg = i % 2 == 0 ? PdfColors.white : PdfColors.grey50;
                  final cells = invoice.isNonStockSale
                      ? [
                          _s(item.productName),
                          item.qty.toString(),
                          _fmtAmt(item.unitPrice),
                          _fmtAmt(item.subtotal),
                        ]
                      : [
                          _s(
                            item.productName,
                          ), // ISSUE-014: sanitize user input
                          _s(item.size),
                          _s(item.color),
                          item.qty.toString(),
                          _fmtAmt(item.unitPrice),
                          _fmtAmt(item.subtotal),
                        ];
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bg),
                    children: cells
                        .map(
                          (c) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: pw.Text(
                              c,
                              style: pw.TextStyle(
                                fontSize: 8,
                                font: primaryFont,
                                fontFallback: ff,
                              ),
                              textAlign: pw.TextAlign.center,
                              textDirection: _cellDir(c, dir),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }),
              ],
            ),
          pw.SizedBox(height: 14),

          if (!isCashReceipt)
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 200,
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pairedLabel(lblSubtotal, style: ts(size: 9)),
                        pw.Text(
                          _fmtAmt(invoice.subtotal),
                          style: ts(size: 9),
                          textDirection: _amountDir,
                        ),
                      ],
                    ),
                    if (invoice.discount > 0) ...[
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pairedLabel(
                            lblDiscount,
                            style: ts(size: 9, color: PdfColors.green700),
                          ),
                          pw.Text(
                            '-${_fmtAmt(invoice.discount)}',
                            style: ts(size: 9, color: PdfColors.green700),
                            textDirection: _amountDir,
                          ),
                        ],
                      ),
                    ],
                    pw.Divider(thickness: 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pairedLabel(
                          _documentLabelWithSuffix(
                            'total',
                            currencyLabel,
                            pair,
                            locale,
                            separator: ' ',
                          ),
                          style: ts(size: 11, fw: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          _fmtAmt(invoice.total),
                          style: ts(size: 11, fw: pw.FontWeight.bold),
                          textDirection: _amountDir,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          pw.SizedBox(height: 14),

          if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
            pairedLabel(
              lblNotes.split('\n').map((line) => '$line:').join('\n'),
              style: ts(size: 9, fw: pw.FontWeight.bold),
            ),
            pw.Text(_s(invoice.notes!), style: ts(size: 9)),
            pw.SizedBox(height: 8),
          ],

          if (invoice.linkedInvoiceId != null &&
              invoice.linkedInvoiceId!.isNotEmpty) ...[
            pairedLabel(
              _documentLabelWithSuffix(
                'reference',
                _s(invoice.linkedInvoiceId!),
                pair,
                locale,
              ),
              style: ts(size: 8, color: PdfColors.grey600),
            ),
          ],
        ],
      ),
    );

    return pdf.save();
  }); // Isolate.run
}

// ─────────────────────────────────────────────────────────────────────────────
// Multi-Shop Ledger  (one PDF, each shop its own section)
// ─────────────────────────────────────────────────────────────────────────────

/// A single shop entry for [buildPdfMultiShopLedger].
class MultiShopLedgerSection {
  final String shopName;

  /// Human-readable route label, e.g. "1 · North Route".
  final String routeLabel;

  /// Pre-computed opening balance (= shop.balance − net of [transactions]).
  final double openingBalance;
  final String currency;

  final List<TransactionModel> transactions;

  const MultiShopLedgerSection({
    required this.shopName,
    required this.routeLabel,
    required this.openingBalance,
    this.currency = 'SAR',
    required this.transactions,
  });
}

/// Fixed-width table cell used on the cover index page.
pw.Widget _coverCell(
  String text,
  double width,
  pw.TextDirection dir,
  pw.Font primaryFont,
  List<pw.Font> ff, {
  bool isHeader = false,
  PdfColor? color,
  bool isBold = false,
}) {
  return pw.Container(
    width: width,
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        right: pw.BorderSide(
          color: isHeader ? PdfColors.blue300 : PdfColors.grey300,
          width: 0.5,
        ),
      ),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: (isHeader || isBold)
            ? pw.FontWeight.bold
            : pw.FontWeight.normal,
        color: isHeader ? PdfColors.white : (color ?? PdfColors.black),
        font: primaryFont,
        fontFallback: ff,
      ),
      textAlign: pw.TextAlign.center,
      textDirection: dir,
      overflow: pw.TextOverflow.clip,
    ),
  );
}

/// Builds a multi-shop CA-grade account-statement PDF.
///
/// Structure:
/// 1. Cover page(s) — company header + grand summary + shop index table.
/// 2. Shop sections — each shop mirrors the single-shop [buildPdfLedger]
///    style with a route banner printed whenever the route changes.
Future<Uint8List> buildPdfMultiShopLedger({
  required String title,
  required String subtitle,
  required String companyName,
  required String generatedBy,
  required List<MultiShopLedgerSection> sections,
  required Map<String, String> labels,
  AppLocale locale = AppLocale.en,
  Uint8List? logoBytes,
  InvoiceHeaderConfig? header,
  String currency = 'SAR',
  bool showEntryBy = false,
  Map<String, String> entryByMap = const {},
}) async {
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  return _pdfCompute(() {
    final fonts = _fontsFromBytes(aB, uB);
    final lc = _PdfLocaleConfig(
      fonts: fonts,
      locale: locale,
      currency: currency,
    );
    final dir = lc.dir;
    final align = lc.align;
    final primaryFont = lc.primaryFont;
    final ff = lc.ff;
    final fallbackCurrency = currency.trim().isEmpty
        ? 'SAR'
        : currency.trim().toUpperCase();
    String sectionCurrency(MultiShopLedgerSection section) {
      final normalized = section.currency.trim().toUpperCase();
      return normalized.isEmpty ? fallbackCurrency : normalized;
    }

    pw.TextStyle ts({
      double size = 9,
      pw.FontWeight fw = pw.FontWeight.normal,
      PdfColor color = PdfColors.black,
    }) => lc.ts(size: size, fw: fw, color: color);

    final pdf = lc.buildDocument();
    final now = DateTime.now();

    // ── Ledger column widths (portrait A4 usable ≈ 539 pt) ──────────────────
    const double dateW = 54;
    const double entryByW = 68;
    const double amtW = 72;
    const double balW = 76;
    const double usable = 539.0;
    final double remarkW = showEntryBy
        ? usable - dateW - entryByW - amtW - amtW - balW
        : usable - dateW - amtW - amtW - balW;
    final colWidths = showEntryBy
        ? [dateW, remarkW, entryByW, amtW, amtW, balW]
        : [dateW, remarkW, amtW, amtW, balW];
    final headerLabels = showEntryBy
        ? [
            _pdfLabel(labels, 'date', locale),
            _pdfLabel(labels, 'description', locale),
            _pdfLabel(labels, 'entry_by', locale),
            _pdfLabel(labels, 'debit', locale),
            _pdfLabel(labels, 'credit', locale),
            _pdfLabel(labels, 'running_balance', locale),
          ]
        : [
            _pdfLabel(labels, 'date', locale),
            _pdfLabel(labels, 'description', locale),
            _pdfLabel(labels, 'debit', locale),
            _pdfLabel(labels, 'credit', locale),
            _pdfLabel(labels, 'running_balance', locale),
          ];
    final colCount = colWidths.length;

    // ── Cover table column widths ────────────────────────────────────────────
    const double cnW = 200.0;
    const double crW = 120.0;
    const double caW = 73.0;
    const double cbW = usable - cnW - crW - caW - caW;

    // ── Pre-compute per-section totals ───────────────────────────────────────
    final sectionFinals = <double>[];
    final sectionTotalCredit = <double>[];
    final sectionTotalDebit = <double>[];
    final balanceByCurrency = <String, double>{};
    for (final sec in sections) {
      final currencyCode = sectionCurrency(sec);
      final summary = calculateLedgerSummary(
        openingBalance: sec.openingBalance,
        transactions: sec.transactions,
      );
      sectionFinals.add(summary.closingBalance);
      sectionTotalCredit.add(summary.totalCredit);
      sectionTotalDebit.add(summary.totalDebit);
      balanceByCurrency.update(
        currencyCode,
        (value) => value + summary.closingBalance,
        ifAbsent: () => summary.closingBalance,
      );
    }
    final balanceSummary = balanceByCurrency.isEmpty
        ? _fmtAmtC(0, pdfCurrencyLabel(locale, fallbackCurrency))
        : balanceByCurrency.entries
              .map(
                (entry) =>
                    _fmtAmtC(entry.value, pdfCurrencyLabel(locale, entry.key)),
              )
              .join(' / ');
    final totalShops = sections.length;

    // ── Cover section with natural, renderer-managed pagination ─────────────
    final coverRows = <pw.Widget>[];
    String? lastCoverRoute;
    for (var si = 0; si < sections.length; si++) {
      final sec = sections[si];
      final finalBal = sectionFinals[si];
      final totalCredit = sectionTotalCredit[si];
      final totalDebit = sectionTotalDebit[si];
      final currencyCode = sectionCurrency(sec);
      final currencyLabel = pdfCurrencyLabel(locale, currencyCode);
      final bg = si % 2 == 0 ? PdfColors.white : PdfColors.grey50;

      if (sec.routeLabel.trim().isNotEmpty &&
          sec.routeLabel != lastCoverRoute) {
        lastCoverRoute = sec.routeLabel;
        coverRows.add(
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(
              color: PdfColors.indigo50,
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.indigo800, width: 3),
                bottom: pw.BorderSide(color: PdfColors.indigo200, width: 0.5),
              ),
            ),
            child: pw.Text(
              _s(sec.routeLabel),
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.indigo800,
                font: primaryFont,
                fontFallback: ff,
              ),
              textDirection: _cellDir(sec.routeLabel, dir),
            ),
          ),
        );
      }

      coverRows.add(
        pw.Container(
          decoration: pw.BoxDecoration(
            color: bg,
            border: const pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
            ),
          ),
          child: pw.Row(
            children: [
              _coverCell(
                _s(sec.shopName),
                cnW,
                _cellDir(sec.shopName, dir),
                primaryFont,
                ff,
              ),
              _coverCell(
                _s(sec.routeLabel),
                crW,
                _cellDir(sec.routeLabel, dir),
                primaryFont,
                ff,
              ),
              _coverCell(
                _fmtAmtC(totalDebit, currencyLabel),
                caW,
                _amountDir,
                primaryFont,
                ff,
                color: totalDebit > 0 ? PdfColors.red800 : null,
              ),
              _coverCell(
                _fmtAmtC(totalCredit, currencyLabel),
                caW,
                _amountDir,
                primaryFont,
                ff,
                color: totalCredit > 0 ? PdfColors.green800 : null,
              ),
              _coverCell(
                _fmtAmtC(finalBal, currencyLabel),
                cbW,
                _amountDir,
                primaryFont,
                ff,
                color: finalBal >= 0 ? PdfColors.red800 : PdfColors.green800,
                isBold: true,
              ),
            ],
          ),
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        textDirection: dir,
        header: (ctx) {
          final widgets = <pw.Widget>[];
          if (ctx.pageNumber == 1) {
            widgets.addAll([
              _workspaceBrandHeader(
                header: header ?? const InvoiceHeaderConfig(),
                fallbackName: companyName,
                localeConfig: lc,
                logoBytes: logoBytes,
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _s(title),
                    style: ts(
                      size: 11,
                      fw: pw.FontWeight.bold,
                      color: _invoiceAccentColor(
                        header?.accentColor ?? '#315C4C',
                      ),
                    ),
                    textDirection: _cellDir(title, dir),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        '${_pdfLabel(labels, 'report_date', locale)}: ${_fmtDate(now)}',
                        style: ts(size: 8, color: PdfColors.grey700),
                        textDirection: dir,
                      ),
                      if (generatedBy.isNotEmpty)
                        pw.Text(
                          '${_pdfLabel(labels, 'generated_by', locale)}: ${_s(generatedBy)}',
                          style: ts(size: 8, color: PdfColors.grey700),
                          textDirection: dir,
                        ),
                      if (subtitle.isNotEmpty)
                        pw.Text(
                          _s(subtitle),
                          style: ts(size: 8, color: PdfColors.grey500),
                          textDirection: dir,
                        ),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.blue800),
              pw.SizedBox(height: 4),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue100, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  children: [
                    _summaryCell(
                      label: _pdfLabel(labels, 'total_entries', locale),
                      value: '$totalShops',
                      color: PdfColors.blue800,
                      primaryFont: primaryFont,
                      direction: dir,
                      ff: ff,
                    ),
                    pw.Container(
                      width: 0.5,
                      height: 40,
                      color: PdfColors.blue100,
                    ),
                    _summaryCell(
                      label: _pdfLabel(labels, 'net_payable', locale),
                      value: balanceSummary,
                      color: PdfColors.blue800,
                      primaryFont: primaryFont,
                      direction: dir,
                      ff: ff,
                      isBold: true,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
            ]);
          }

          widgets.add(
            pw.Container(
              decoration: const pw.BoxDecoration(color: PdfColors.blue800),
              child: pw.Row(
                children: [
                  _coverCell(
                    _pdfLabel(labels, 'name', locale),
                    cnW,
                    dir,
                    primaryFont,
                    ff,
                    isHeader: true,
                  ),
                  _coverCell(
                    _pdfLabel(labels, 'route', locale),
                    crW,
                    dir,
                    primaryFont,
                    ff,
                    isHeader: true,
                  ),
                  _coverCell(
                    _pdfLabel(labels, 'debit', locale),
                    caW,
                    dir,
                    primaryFont,
                    ff,
                    isHeader: true,
                  ),
                  _coverCell(
                    _pdfLabel(labels, 'credit', locale),
                    caW,
                    dir,
                    primaryFont,
                    ff,
                    isHeader: true,
                  ),
                  _coverCell(
                    _pdfLabel(labels, 'running_balance', locale),
                    cbW,
                    dir,
                    primaryFont,
                    ff,
                    isHeader: true,
                  ),
                ],
              ),
            ),
          );

          return pw.Column(crossAxisAlignment: align, children: widgets);
        },
        footer: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                '${_pdfLabel(labels, 'page', locale)} ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: ts(size: 7, color: PdfColors.grey500),
              ),
            ),
          ],
        ),
        build: (ctx) => [...coverRows],
      ),
    );

    // ── Per-shop section pages (migrated to MultiPage per-section to avoid
    // fixed-row clipping issues when final balances or summary blocks are appended)
    for (var si = 0; si < sections.length; si++) {
      final sec = sections[si];
      final finalBal = sectionFinals[si];
      final totalCredit = sectionTotalCredit[si];
      final totalDebit = sectionTotalDebit[si];
      final currencyCode = sectionCurrency(sec);
      final currencyLabel = pdfCurrencyLabel(locale, currencyCode);

      // Build ledger rows for this shop
      var balance = sec.openingBalance;
      final sortedTx = [...sec.transactions]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final entryCount = sortedTx.length;
      final shopRows = <_LedgerRow>[];

      if (sec.openingBalance != 0) {
        shopRows.add(
          _LedgerRow(
            date: '',
            desc: _pdfLabel(labels, 'opening_balance', locale),
            entryBy: '',
            mode: '',
            cashIn: 0,
            cashOut: 0,
            balance: sec.openingBalance,
          ),
        );
      }

      for (final tx in sortedTx) {
        final date = tx.createdAt.toDate();
        final rawDesc = tx.description?.isNotEmpty == true
            ? _s(tx.description!)
            : (tx.hasItems
                  ? tx.items.map((i) => _s(i.productName)).join(', ')
                  : '');
        final desc = tx.invoiceNumber != null && tx.invoiceNumber!.isNotEmpty
            ? '[${_s(tx.invoiceNumber!)}] $rawDesc'
            : rawDesc;
        final entryBy = showEntryBy ? (entryByMap[tx.createdBy] ?? '—') : '';
        final mode = tx.saleType ?? '';
        final impact = tx.balanceImpact;
        balance += impact;
        if (impact >= 0) {
          shopRows.add(
            _LedgerRow(
              date: _fmtDate(date),
              desc: desc,
              entryBy: entryBy,
              mode: mode,
              cashIn: 0,
              cashOut: impact,
              balance: balance,
            ),
          );
        } else {
          shopRows.add(
            _LedgerRow(
              date: _fmtDate(date),
              desc: desc,
              entryBy: entryBy,
              mode: mode,
              cashIn: -impact,
              cashOut: 0,
              balance: balance,
            ),
          );
        }
      }

      // Create a MultiPage document for this shop section so rows flow naturally
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          textDirection: dir,
          header: (ctx) {
            if (ctx.pageNumber == 1) {
              final widgets = <pw.Widget>[];
              if (sec.routeLabel.trim().isNotEmpty) {
                widgets.add(
                  pw.Container(
                    width: double.infinity,
                    margin: const pw.EdgeInsets.only(bottom: 6),
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.indigo800,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      _s(sec.routeLabel),
                      style: ts(
                        size: 10,
                        fw: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                      textDirection: _cellDir(sec.routeLabel, dir),
                    ),
                  ),
                );
              }
              widgets.addAll([
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.only(bottom: 4),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blue50,
                    border: pw.Border(
                      left: pw.BorderSide(color: PdfColors.blue800, width: 3),
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        _s(sec.shopName),
                        style: ts(size: 12, fw: pw.FontWeight.bold),
                        textDirection: _cellDir(sec.shopName, dir),
                      ),
                      pw.Text(
                        '${_pdfLabel(labels, 'report_date', locale)}: ${_fmtDate(now)}  |  ${_pdfLabel(labels, 'generated_by', locale)}: ${_s(generatedBy)}',
                        style: ts(size: 7, color: PdfColors.grey700),
                        textDirection: dir,
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue100, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    children: [
                      _summaryCell(
                        label: _pdfLabel(labels, 'credit', locale),
                        value: _fmtAmtC(totalCredit, currencyLabel),
                        color: PdfColors.green800,
                        primaryFont: primaryFont,
                        direction: dir,
                        ff: ff,
                      ),
                      pw.Container(
                        width: 0.5,
                        height: 40,
                        color: PdfColors.blue100,
                      ),
                      _summaryCell(
                        label: _pdfLabel(labels, 'debit', locale),
                        value: _fmtAmtC(totalDebit, currencyLabel),
                        color: PdfColors.red800,
                        primaryFont: primaryFont,
                        direction: dir,
                        ff: ff,
                      ),
                      pw.Container(
                        width: 0.5,
                        height: 40,
                        color: PdfColors.blue100,
                      ),
                      _summaryCell(
                        label: _pdfLabel(labels, 'net_payable', locale),
                        value: _fmtAmtC(finalBal.abs(), currencyLabel),
                        color: finalBal >= 0
                            ? PdfColors.red800
                            : PdfColors.green800,
                        primaryFont: primaryFont,
                        direction: dir,
                        ff: ff,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${_pdfLabel(labels, 'total_entries', locale)}: $entryCount',
                  style: ts(size: 8, color: PdfColors.grey600),
                  textDirection: dir,
                ),
                pw.SizedBox(height: 6),
                _buildLedgerHeaderRow(
                  headerLabels,
                  colWidths,
                  colCount,
                  dir,
                  primaryFont,
                  ff,
                ),
              ]);
              return pw.Column(crossAxisAlignment: align, children: widgets);
            }
            // subsequent pages: small continuation header
            return pw.Column(
              children: [
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.only(bottom: 4),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                  child: pw.Text(
                    '${_s(sec.shopName)} (cont.)',
                    style: ts(size: 9, fw: pw.FontWeight.bold),
                    textDirection: _cellDir(sec.shopName, dir),
                  ),
                ),
                _buildLedgerHeaderRow(
                  headerLabels,
                  colWidths,
                  colCount,
                  dir,
                  primaryFont,
                  ff,
                ),
              ],
            );
          },
          footer: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${_s(sec.shopName)} — ${_pdfLabel(labels, 'page', locale)} ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: ts(size: 7, color: PdfColors.grey500),
                ),
              ),
            ],
          ),
          build: (ctx) => [
            ...shopRows.asMap().entries.map((e) {
              final idx = e.key;
              final r = e.value;
              final bg = idx % 2 == 0 ? PdfColors.white : PdfColors.grey50;
              return _buildLedgerDataRow(
                r,
                colWidths,
                colCount,
                bg,
                dir,
                primaryFont,
                ff,
                showEntryBy,
                currencyLabel,
              );
            }),
            // final balance placed as flow item so it will not clip rows
            pw.Container(
              decoration: const pw.BoxDecoration(
                color: PdfColors.blue50,
                border: pw.Border(
                  left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                  right: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                ),
              ),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: colWidths
                        .take(colCount - 1)
                        .fold<double>(0, (a, b) => a + b),
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        right: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: pw.Text(
                      _pdfLabel(labels, 'net_payable', locale),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                        font: primaryFont,
                        fontFallback: ff,
                      ),
                      textDirection: dir,
                    ),
                  ),
                  pw.Container(
                    width: colWidths.last,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: pw.Text(
                      _fmtAmtC(finalBal, currencyLabel),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: finalBal >= 0
                            ? PdfColors.red800
                            : PdfColors.green800,
                        font: primaryFont,
                        fontFallback: ff,
                      ),
                      textDirection: _amountDir,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return pdf.save();
  }); // Isolate.run
}
