import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../l10n/app_locale.dart';
import '../../models/transaction_model.dart';
import '../../models/invoice_model.dart';

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

/// Centralised locale → font/direction/currency configuration for all PDF
/// builders. Eliminates the previously 5× duplicated inline computation.
///
/// **Font policy:** NotoSansArabic is PRIMARY for ALL locales (including Urdu).
/// NotoNastaliqUrdu is kept as fallback only. The pdf package's TrueType
/// renderer cannot handle Nastaliq's complex GSUB/GPOS shaping tables —
/// using it as primary causes boxes and scattered characters.
class _PdfLocaleConfig {
  final bool isRtl;
  final pw.TextDirection dir;
  final pw.CrossAxisAlignment align;
  final pw.Font primaryFont;
  final List<pw.Font> ff;
  final String currencyStr;

  _PdfLocaleConfig._({
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
      isRtl: isRtl,
      dir: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      align: isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      // NotoSansArabic covers full Arabic-script Unicode (including Urdu
      // characters) in Naskh style. Always primary for PDF rendering.
      primaryFont: fonts.arabic,
      ff: <pw.Font>[fonts.urdu],
      currencyStr: locale == AppLocale.ar
          ? 'ريال'
          : locale == AppLocale.ur
          ? 'ریال'
          : currency,
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
                if (logoBytes != null)
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
                  (pageLabel ?? 'Page %1 of %2')
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

String _fmtAmt(double v) => v.toStringAsFixed(2);
String _fmtAmtC(double v, String currency) => currency.isEmpty
    ? v.toStringAsFixed(2)
    : '${v.toStringAsFixed(2)} $currency';

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
    'cash_in',
    'cash_out',
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
    double balance = openingBalance;
    double totalCashIn = 0;
    double totalCashOut = 0;
    final int entryCount = transactions.length;

    final rows = <_LedgerRow>[];
    // Insert an opening-balance row so the final running balance is
    // always reconcilable to the stored account balance.
    if (openingBalance != 0) {
      rows.add(
        _LedgerRow(
          date: '',
          desc: labels['opening_balance'] ?? 'Opening Balance',
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

      if (tx.isCashOut) {
        balance += tx.amount;
        totalCashOut += tx.amount;
        rows.add(
          _LedgerRow(
            date: _fmtDate(date),
            desc: desc,
            entryBy: entryBy,
            mode: mode,
            cashIn: 0,
            cashOut: tx.amount,
            balance: balance,
          ),
        );
      } else {
        balance -= tx.amount;
        totalCashIn += tx.amount;
        rows.add(
          _LedgerRow(
            date: _fmtDate(date),
            desc: desc,
            entryBy: entryBy,
            mode: mode,
            cashIn: tx.amount,
            cashOut: 0,
            balance: balance,
          ),
        );
      }
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
            labels['date'] ?? 'Date',
            labels['description'] ?? 'Remark',
            labels['entry_by'] ?? 'Entry By',
            labels['debit'] ?? 'Cash Out',
            labels['credit'] ?? 'Cash In',
            labels['running_balance'] ?? 'Balance',
          ]
        : [
            labels['date'] ?? 'Date',
            labels['description'] ?? 'Remark',
            labels['debit'] ?? 'Cash Out',
            labels['credit'] ?? 'Cash In',
            labels['running_balance'] ?? 'Balance',
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
                // ── Header ──
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logoBytes != null) ...[
                          pw.Image(
                            pw.MemoryImage(logoBytes),
                            height: 36,
                            fit: pw.BoxFit.contain,
                          ),
                          pw.SizedBox(width: 8),
                        ],
                        pw.Column(
                          crossAxisAlignment: align,
                          children: [
                            pw.Text(
                              _s(companyName),
                              style: ts(size: 16, fw: pw.FontWeight.bold),
                              textDirection: _cellDir(companyName, dir),
                            ),
                            pw.Text(
                              labels['account_statement'] ?? 'Account Statement',
                              style: ts(
                                size: 11,
                                fw: pw.FontWeight.bold,
                                color: PdfColors.blue800,
                              ),
                              textDirection: dir,
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          '${labels['report_date'] ?? 'Generated On'}: ${_fmtDate(now)}',
                          style: ts(size: 8, color: PdfColors.grey700),
                          textDirection: dir,
                        ),
                        if (generatedBy.isNotEmpty)
                          pw.Text(
                            '${labels['generated_by'] ?? 'By'}: ${_s(generatedBy)}',
                            style: ts(size: 8, color: PdfColors.grey700),
                            textDirection: dir,
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
                    child: pw.Text(
                      '${labels['duration'] ?? 'Duration'}: ${_fmtDate(dateFrom)} — ${_fmtDate(dateTo)}',
                      style: ts(size: 8, color: PdfColors.grey700),
                      textDirection: dir,
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
                        label: labels['cash_in'] ?? 'Total Cash In',
                        value: _fmtAmtC(totalCashIn, currencyStr),
                        color: PdfColors.green800,
                        primaryFont: primaryFont,
                        ff: ff,
                      ),
                      pw.Container(
                        width: 0.5,
                        height: 40,
                        color: PdfColors.blue100,
                      ),
                      _summaryCell(
                        label: labels['cash_out'] ?? 'Total Cash Out',
                        value: _fmtAmtC(totalCashOut, currencyStr),
                        color: PdfColors.red800,
                        primaryFont: primaryFont,
                        ff: ff,
                      ),
                      pw.Container(
                        width: 0.5,
                        height: 40,
                        color: PdfColors.blue100,
                      ),
                      _summaryCell(
                        label: labels['net_payable'] ?? 'Final Balance',
                        value: _fmtAmtC(balance.abs(), currencyStr),
                        color: balance > 0 ? PdfColors.red800 : PdfColors.green800,
                        primaryFont: primaryFont,
                        ff: ff,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${labels['total_entries'] ?? 'Total entries'}: $entryCount',
                  style: ts(size: 8, color: PdfColors.grey600),
                  textDirection: dir,
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
              child: pw.Text(
                '${labels['page'] ?? 'Page'} ${ctx.pageNumber} / ${ctx.pagesCount}',
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
                  width: colWidths.take(colCount - 1).fold<double>(0, (a, b) => a + b),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                    ),
                  ),
                  child: pw.Text(
                    labels['net_payable'] ?? 'Final Balance',
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
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  child: pw.Text(
                    _fmtAmtC(balance, currencyStr),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: balance > 0 ? PdfColors.red800 : PdfColors.green800,
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
  required List<pw.Font> ff,
  bool isBold = false,
}) {
  return pw.Expanded(
    child: pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey600,
              font: primaryFont,
              fontFallback: ff,
            ),
            textAlign: pw.TextAlign.center,
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
          child: pw.Text(
            labels[i],
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              font: primaryFont,
              fontFallback: ff,
            ),
            textAlign: pw.TextAlign.center,
            textDirection: _cellDir(labels[i], dir),
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
  const SellerReportShop({
    required this.name,
    required this.totalPairsSold,
    required this.totalRevenue,
    required this.outstandingBalance,
  });
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

    double totalRevenue = 0;
    double totalOutstanding = 0;
    int totalPairs = 0;
    for (final c in shops) {
      totalRevenue += c.totalRevenue;
      totalOutstanding += c.outstandingBalance;
      totalPairs += c.totalPairsSold;
    }

    final pdf = lc.buildDocument();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        textDirection: dir,
        build: (ctx) => [
          // ── Title ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoBytes != null) ...[
                    pw.Image(
                      pw.MemoryImage(logoBytes),
                      height: 32,
                      fit: pw.BoxFit.contain,
                    ),
                    pw.SizedBox(width: 8),
                  ],
                  pw.Column(
                    crossAxisAlignment: isRtl
                        ? pw.CrossAxisAlignment.end
                        : pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _s(companyName),
                        style: ts(size: 18, fw: pw.FontWeight.bold),
                        textDirection: _cellDir(companyName, dir),
                      ),
                      pw.Text(
                        labels['seller_report'] ?? 'Seller Report',
                        style: ts(
                          size: 13,
                          fw: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                        ),
                        textDirection: dir,
                      ),
                    ],
                  ),
                ],
              ),
              pw.Text(
                '${labels['report_date'] ?? 'Date'}: ${_fmtDate(DateTime.now())}',
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
                      '${labels['seller'] ?? 'Seller'}: ${_s(sellerName)}',
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
                  '${labels['route'] ?? 'Route'}: ${_s(routeName)}',
                  style: ts(size: 10, fw: pw.FontWeight.bold),
                  textDirection: _cellDir(routeName, dir),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // ── Stock Summary ──
          pw.Text(
            labels['inventory'] ?? 'Stock Summary',
            style: ts(size: 11, fw: pw.FontWeight.bold),
            textDirection: dir,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              _stockCard(
                labels['stock_received'] ?? 'Received',
                stockReceived.toString(),
                PdfColors.blue50,
                primaryFont: primaryFont,
                ff: ff,
              ),
              pw.SizedBox(width: 8),
              _stockCard(
                labels['stock_sold'] ?? 'Sold',
                stockSold.toString(),
                PdfColors.orange50,
                primaryFont: primaryFont,
                ff: ff,
              ),
              pw.SizedBox(width: 8),
              _stockCard(
                labels['stock_remaining'] ?? 'Remaining',
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
            labels['shops'] ?? 'Shops',
            style: ts(size: 11, fw: pw.FontWeight.bold),
            textDirection: dir,
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers:
                [
                      labels['shop'] ?? 'Shop',
                      labels['stock_sold'] ?? 'Sold (Pairs)',
                      labels['revenue'] ?? 'Revenue',
                      labels['outstanding'] ?? 'Outstanding',
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
                    _fmtAmt(c.totalRevenue),
                    _fmtAmt(c.outstandingBalance),
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
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${labels['total'] ?? 'Total'} ${labels['stock_sold'] ?? 'Sold'}: $totalPairs ${labels['pairs'] ?? 'pairs'}',
                  style: ts(size: 9, fw: pw.FontWeight.bold),
                  textDirection: dir,
                ),
                pw.Text(
                  '${labels['revenue'] ?? 'Revenue'}: ${_fmtAmt(totalRevenue)}',
                  style: ts(size: 9, fw: pw.FontWeight.bold),
                  textDirection: dir,
                ),
                pw.Text(
                  '${labels['outstanding'] ?? 'Outstanding'}: ${_fmtAmt(totalOutstanding)}',
                  style: ts(
                    size: 9,
                    fw: pw.FontWeight.bold,
                    color: totalOutstanding > 0
                        ? PdfColors.red700
                        : PdfColors.green700,
                  ),
                  textDirection: dir,
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
}) async {
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  final lblSubtotal = trRead('subtotal', locale);
  final lblDiscount = trRead('discount', locale);
  final lblNotes = trRead('notes', locale);
  final lblInvoiceTitle = trRead('invoice_title', locale);
  final lblCreditNote = trRead('credit_note', locale);
  final lblDate = trRead('date', locale);
  final lblShop = trRead('shop', locale);
  final lblItem = trRead('item_number', locale);
  final lblSize = trRead('size', locale);
  final lblColor = trRead('color', locale);
  final lblQty = trRead('qty', locale);
  final lblUnitPrice = trRead('unit_price', locale);
  final lblTotal = trRead('total', locale);
  final lblReference = trRead('reference', locale);
  final lblVoid = trRead('void', locale);
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

    final date = invoice.createdAt.toDate();
    final dateStr = _fmtDate(date);
    final isCreditNote = invoice.type != InvoiceModel.typeSale;
    final docTitle = isCreditNote ? lblCreditNote : lblInvoiceTitle;

    final pdf = _buildDocument(primaryFont, ff);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        textDirection: dir,
        build: (ctx) => pw.Column(
          crossAxisAlignment: align,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoBytes != null) ...[
                      pw.Image(
                        pw.MemoryImage(logoBytes),
                        height: 36,
                        fit: pw.BoxFit.contain,
                      ),
                      pw.SizedBox(width: 8),
                    ],
                    pw.Column(
                      crossAxisAlignment: align,
                      children: [
                        pw.Text(
                          _s(companyName),
                          style: ts(size: 16, fw: pw.FontWeight.bold),
                          textDirection: _cellDir(companyName, dir),
                        ),
                        pw.Text(
                          docTitle,
                          style: ts(
                            size: 13,
                            fw: pw.FontWeight.bold,
                            color: isCreditNote
                                ? PdfColors.green800
                                : PdfColors.blue800,
                          ),
                          textDirection: dir,
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '# ${invoice.invoiceNumber}',
                      style: ts(size: 12, fw: pw.FontWeight.bold),
                      textDirection: dir,
                    ),
                    pw.Text(
                      '$lblDate: $dateStr',
                      style: ts(size: 9, color: PdfColors.grey700),
                      textDirection: dir,
                    ),
                    if (invoice.status == 'void')
                      pw.Text(
                        lblVoid.toUpperCase(),
                        style: ts(
                          size: 14,
                          fw: pw.FontWeight.bold,
                          color: PdfColors.red,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1.5, color: PdfColors.blue800),
            pw.SizedBox(height: 10),

            // Customer info
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
                  pw.Text(
                    '$lblShop: ${_s(invoice.shopName)}',
                    style: ts(size: 10, fw: pw.FontWeight.bold),
                    textDirection: _cellDir(invoice.shopName, dir),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Items table
            if (invoice.items.isNotEmpty)
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                columnWidths: {
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
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue800,
                    ),
                    children:
                        [
                              lblItem,
                              lblSize,
                              lblColor,
                              lblQty,
                              lblUnitPrice,
                              lblTotal,
                            ]
                            .map(
                              (h) => pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 5,
                                ),
                                child: pw.Text(
                                  h,
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white,
                                    font: primaryFont,
                                    fontFallback: ff,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                  textDirection: dir,
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
                    final cells = [
                      _s(item.productName), // ISSUE-014: sanitize user input
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

            // Totals
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 200,
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          lblSubtotal,
                          style: ts(size: 9),
                          textDirection: dir,
                        ),
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
                          pw.Text(
                            lblDiscount,
                            style: ts(size: 9, color: PdfColors.green700),
                            textDirection: dir,
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
                        pw.Text(
                          '$lblTotal $currencyLabel',
                          style: ts(size: 11, fw: pw.FontWeight.bold),
                          textDirection: dir,
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
              pw.Text('$lblNotes:', style: ts(size: 9, fw: pw.FontWeight.bold)),
              pw.Text(_s(invoice.notes!), style: ts(size: 9)),
              pw.SizedBox(height: 8),
            ],

            if (invoice.linkedInvoiceId != null &&
                invoice.linkedInvoiceId!.isNotEmpty) ...[
              pw.Text(
                '$lblReference: ${_s(invoice.linkedInvoiceId!)}', // ISSUE-036
                style: ts(size: 8, color: PdfColors.grey600),
              ),
            ],

            pw.Spacer(),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.Text(
              '${_s(companyName)} • $dateStr',
              style: ts(size: 7, color: PdfColors.grey500),
            ),
          ],
        ),
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

  final List<TransactionModel> transactions;

  const MultiShopLedgerSection({
    required this.shopName,
    required this.routeLabel,
    required this.openingBalance,
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
    final currencyStr = lc.currencyStr;
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
            labels['date'] ?? 'Date',
            labels['description'] ?? 'Remark',
            labels['entry_by'] ?? 'Entry By',
            labels['debit'] ?? 'Debit',
            labels['credit'] ?? 'Credit',
            labels['running_balance'] ?? 'Balance',
          ]
        : [
            labels['date'] ?? 'Date',
            labels['description'] ?? 'Remark',
            labels['debit'] ?? 'Debit',
            labels['credit'] ?? 'Credit',
            labels['running_balance'] ?? 'Balance',
          ];
    final colCount = colWidths.length;

    // ── Cover table column widths ────────────────────────────────────────────
    const double cnW = 200.0;
    const double crW = 120.0;
    const double caW = 73.0;
    const double cbW = usable - cnW - crW - caW - caW;

    // ── Pre-compute per-section totals ───────────────────────────────────────
    final sectionFinals = <double>[];
    final sectionTotalIn = <double>[];
    final sectionTotalOut = <double>[];
    for (final sec in sections) {
      var bal = sec.openingBalance;
      var tIn = 0.0;
      var tOut = 0.0;
      for (final tx in sec.transactions) {
        final impact = tx.balanceImpact; // 0 for unknown types — safe
        bal += impact;
        if (impact > 0) {
          tOut += impact; // positive impact = cash_out = debit (shop owes more)
        } else if (impact < 0) {
          tIn -= impact; // negative impact = cash_in/return/payment = credit
        }
        // write_off (impact == 0) and unknown types: excluded from In/Out totals
      }
      sectionFinals.add(bal);
      sectionTotalIn.add(tIn);
      sectionTotalOut.add(tOut);
    }
    final grandBalance = sectionFinals.fold(0.0, (s, b) => s + b);
    final totalShops = sections.length;

    // ── Cover page(s) ────────────────────────────────────────────────────────
    const coverRowsPerPage = 28;
    final coverPageCount = totalShops == 0
        ? 1
        : ((totalShops / coverRowsPerPage).ceil());

    for (var cp = 0; cp < coverPageCount; cp++) {
      final isFirstCover = cp == 0;
      final sl = cp * coverRowsPerPage;
      final sl2 = (sl + coverRowsPerPage).clamp(0, totalShops);
      final pageRows = sections.sublist(sl, sl2);
      final pageIdxBase = sl;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          textDirection: dir,
          build: (ctx) => pw.Column(
            crossAxisAlignment: align,
            children: [
              if (isFirstCover) ...[
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logoBytes != null) ...[
                          pw.Image(
                            pw.MemoryImage(logoBytes),
                            height: 36,
                            fit: pw.BoxFit.contain,
                          ),
                          pw.SizedBox(width: 8),
                        ],
                        pw.Column(
                          crossAxisAlignment: align,
                          children: [
                            pw.Text(
                              _s(companyName),
                              style: ts(size: 16, fw: pw.FontWeight.bold),
                              textDirection: _cellDir(companyName, dir),
                            ),
                            pw.Text(
                              _s(title),
                              style: ts(
                                size: 11,
                                fw: pw.FontWeight.bold,
                                color: PdfColors.blue800,
                              ),
                              textDirection: dir,
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          '${labels['report_date'] ?? 'Generated'}: ${_fmtDate(now)}',
                          style: ts(size: 8, color: PdfColors.grey700),
                          textDirection: dir,
                        ),
                        if (generatedBy.isNotEmpty)
                          pw.Text(
                            '${labels['generated_by'] ?? 'By'}: ${_s(generatedBy)}',
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
                        label: labels['total_entries'] ?? 'Total Shops',
                        value: '$totalShops',
                        color: PdfColors.blue800,
                        primaryFont: primaryFont,
                        ff: ff,
                      ),
                      pw.Container(
                        width: 0.5,
                        height: 40,
                        color: PdfColors.blue100,
                      ),
                      _summaryCell(
                        label: labels['net_payable'] ?? 'Total Outstanding',
                        value: _fmtAmtC(grandBalance.abs(), currencyStr),
                        color: grandBalance >= 0
                            ? PdfColors.red800
                            : PdfColors.green800,
                        primaryFont: primaryFont,
                        ff: ff,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
              ],
              // Cover index table header
              pw.Container(
                decoration: const pw.BoxDecoration(color: PdfColors.blue800),
                child: pw.Row(
                  children: [
                    _coverCell(
                      labels['name'] ?? 'Shop',
                      cnW,
                      dir,
                      primaryFont,
                      ff,
                      isHeader: true,
                    ),
                    _coverCell(
                      labels['route'] ?? 'Route',
                      crW,
                      dir,
                      primaryFont,
                      ff,
                      isHeader: true,
                    ),
                    _coverCell(
                      labels['debit'] ?? 'Debit',
                      caW,
                      dir,
                      primaryFont,
                      ff,
                      isHeader: true,
                    ),
                    _coverCell(
                      labels['credit'] ?? 'Credit',
                      caW,
                      dir,
                      primaryFont,
                      ff,
                      isHeader: true,
                    ),
                    _coverCell(
                      labels['running_balance'] ?? 'Balance',
                      cbW,
                      dir,
                      primaryFont,
                      ff,
                      isHeader: true,
                    ),
                  ],
                ),
              ),
              // Cover index table rows — with route separator rows
              ...() {
                final widgets = <pw.Widget>[];
                String? lastCoverRoute;
                for (var ei = 0; ei < pageRows.length; ei++) {
                  final gi = pageIdxBase + ei;
                  final sec = pageRows[ei];
                  final finalBal = sectionFinals[gi];
                  final tIn = sectionTotalIn[gi];
                  final tOut = sectionTotalOut[gi];
                  final bg = ei % 2 == 0 ? PdfColors.white : PdfColors.grey50;
                  // Insert route separator when route changes
                  if (sec.routeLabel.trim().isNotEmpty &&
                      sec.routeLabel != lastCoverRoute) {
                    lastCoverRoute = sec.routeLabel;
                    widgets.add(
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.indigo50,
                          border: pw.Border(
                            left: pw.BorderSide(
                              color: PdfColors.indigo800,
                              width: 3,
                            ),
                            bottom: pw.BorderSide(
                              color: PdfColors.indigo200,
                              width: 0.5,
                            ),
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
                  widgets.add(
                    pw.Container(
                      decoration: pw.BoxDecoration(
                        color: bg,
                        border: const pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey200,
                            width: 0.5,
                          ),
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
                            _fmtAmtC(tOut, currencyStr),
                            caW,
                            _amountDir,
                            primaryFont,
                            ff,
                            color: tOut > 0 ? PdfColors.red800 : null,
                          ),
                          _coverCell(
                            _fmtAmtC(tIn, currencyStr),
                            caW,
                            _amountDir,
                            primaryFont,
                            ff,
                            color: tIn > 0 ? PdfColors.green800 : null,
                          ),
                          _coverCell(
                            _fmtAmtC(finalBal, currencyStr),
                            cbW,
                            _amountDir,
                            primaryFont,
                            ff,
                            color: finalBal >= 0
                                ? PdfColors.red800
                                : PdfColors.green800,
                            isBold: true,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return widgets;
              }(),
              pw.Spacer(),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${labels['page'] ?? 'Page'} ${cp + 1} / $coverPageCount',
                  style: ts(size: 7, color: PdfColors.grey500),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Per-shop section pages (migrated to MultiPage per-section to avoid
    // fixed-row clipping issues when final balances or summary blocks are appended)
    for (var si = 0; si < sections.length; si++) {
      final sec = sections[si];
      final finalBal = sectionFinals[si];
      final tIn = sectionTotalIn[si];
      final tOut = sectionTotalOut[si];

      // Build ledger rows for this shop
      var balance = sec.openingBalance;
      final sortedTx = [...sec.transactions]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final entryCount = sortedTx.length;
      final shopRows = <_LedgerRow>[];

      if (sec.openingBalance != 0) {
        shopRows.add(
          _LedgerRow(
            date: '',
            desc: labels['opening_balance'] ?? 'Opening Balance',
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
            : (tx.hasItems ? tx.items.map((i) => _s(i.productName)).join(', ') : '');
        final desc = tx.invoiceNumber != null && tx.invoiceNumber!.isNotEmpty ? '[${_s(tx.invoiceNumber!)}] $rawDesc' : rawDesc;
        final entryBy = showEntryBy ? (entryByMap[tx.createdBy] ?? '—') : '';
        final mode = tx.saleType ?? '';
        final impact = tx.balanceImpact;
        balance += impact;
        if (impact >= 0) {
          shopRows.add(_LedgerRow(date: _fmtDate(date), desc: desc, entryBy: entryBy, mode: mode, cashIn: 0, cashOut: impact, balance: balance));
        } else {
          shopRows.add(_LedgerRow(date: _fmtDate(date), desc: desc, entryBy: entryBy, mode: mode, cashIn: -impact, cashOut: 0, balance: balance));
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
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: pw.BoxDecoration(color: PdfColors.indigo800, borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Text(_s(sec.routeLabel), style: ts(size: 10, fw: pw.FontWeight.bold, color: PdfColors.white), textDirection: _cellDir(sec.routeLabel, dir)),
                  ),
                );
              }
              widgets.addAll([
                pw.Container(
                  width: double.infinity,
                  margin: const pw.EdgeInsets.only(bottom: 4),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: const pw.BoxDecoration(color: PdfColors.blue50, border: pw.Border(left: pw.BorderSide(color: PdfColors.blue800, width: 3))),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(_s(sec.shopName), style: ts(size: 12, fw: pw.FontWeight.bold), textDirection: _cellDir(sec.shopName, dir)),
                      pw.Text('${labels['report_date'] ?? 'Date'}: ${_fmtDate(now)}  |  ${labels['generated_by'] ?? 'By'}: ${_s(generatedBy)}', style: ts(size: 7, color: PdfColors.grey700), textDirection: dir),
                    ],
                  ),
                ),
                pw.Container(
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blue100, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
                  child: pw.Row(
                    children: [
                      _summaryCell(label: labels['cash_in'] ?? 'Cash In', value: _fmtAmtC(tIn, currencyStr), color: PdfColors.green800, primaryFont: primaryFont, ff: ff),
                      pw.Container(width: 0.5, height: 40, color: PdfColors.blue100),
                      _summaryCell(label: labels['cash_out'] ?? 'Cash Out', value: _fmtAmtC(tOut, currencyStr), color: PdfColors.red800, primaryFont: primaryFont, ff: ff),
                      pw.Container(width: 0.5, height: 40, color: PdfColors.blue100),
                      _summaryCell(label: labels['net_payable'] ?? 'Balance', value: _fmtAmtC(finalBal.abs(), currencyStr), color: finalBal >= 0 ? PdfColors.red800 : PdfColors.green800, primaryFont: primaryFont, ff: ff, isBold: true),
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('${labels['total_entries'] ?? 'Total entries'}: $entryCount', style: ts(size: 8, color: PdfColors.grey600), textDirection: dir),
                pw.SizedBox(height: 6),
                _buildLedgerHeaderRow(headerLabels, colWidths, colCount, dir, primaryFont, ff),
              ]);
              return pw.Column(crossAxisAlignment: align, children: widgets);
            }
            // subsequent pages: small continuation header
            return pw.Column(children: [pw.Container(width: double.infinity, margin: const pw.EdgeInsets.only(bottom: 4), padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: const pw.BoxDecoration(color: PdfColors.blue50), child: pw.Text('${_s(sec.shopName)} (cont.)', style: ts(size: 9, fw: pw.FontWeight.bold), textDirection: _cellDir(sec.shopName, dir)),), _buildLedgerHeaderRow(headerLabels, colWidths, colCount, dir, primaryFont, ff)]);
          },
          footer: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [pw.Divider(thickness: 0.5, color: PdfColors.grey400), pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('${_s(sec.shopName)} — ${labels['page'] ?? 'Page'} ${ctx.pageNumber} / ${ctx.pagesCount}', style: ts(size: 7, color: PdfColors.grey500),),),]),
          build: (ctx) => [
            ...shopRows.asMap().entries.map((e) {
              final idx = e.key;
              final r = e.value;
              final bg = idx % 2 == 0 ? PdfColors.white : PdfColors.grey50;
              return _buildLedgerDataRow(r, colWidths, colCount, bg, dir, primaryFont, ff, showEntryBy, currencyStr);
            }),
            // final balance placed as flow item so it will not clip rows
            pw.Container(
              decoration: const pw.BoxDecoration(color: PdfColors.blue50, border: pw.Border(left: pw.BorderSide(color: PdfColors.grey400, width: 0.5), right: pw.BorderSide(color: PdfColors.grey400, width: 0.5), bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5))),
              child: pw.Row(children: [pw.Container(width: colWidths.take(colCount - 1).fold<double>(0, (a, b) => a + b), padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5), decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),), child: pw.Text(labels['net_payable'] ?? 'Final Balance', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800, font: primaryFont, fontFallback: ff,), textDirection: dir,),), pw.Container(width: colWidths.last, padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5), child: pw.Text(_fmtAmtC(finalBal, currencyStr), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: finalBal >= 0 ? PdfColors.red800 : PdfColors.green800, font: primaryFont, fontFallback: ff,), textDirection: _amountDir,),),]),
            ),
          ],
        ),
      );
    }

    return pdf.save();
  }); // Isolate.run
}
