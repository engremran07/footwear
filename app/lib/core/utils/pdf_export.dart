import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../l10n/app_locale.dart';
import '../../models/transaction_model.dart';
import '../../models/invoice_model.dart';

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
    _arabicFontBytes = ad.buffer.asUint8List(
      ad.offsetInBytes,
      ad.lengthInBytes,
    );
    final ud = await rootBundle.load('assets/fonts/NotoNastaliqUrdu.ttf');
    _urduFontBytes = ud.buffer.asUint8List(ud.offsetInBytes, ud.lengthInBytes);
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
    arabic: pw.Font.ttf(ByteData.view(arabicBytes.buffer)),
    urdu: pw.Font.ttf(ByteData.view(urduBytes.buffer)),
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
}) async {
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  return Isolate.run(() {
    final fonts = _fontsFromBytes(aB, uB);
    final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
    final primaryFont = locale == AppLocale.ur ? fonts.urdu : fonts.arabic;
    final fontFallback = locale == AppLocale.ur
        ? <pw.Font>[fonts.arabic]
        : <pw.Font>[fonts.urdu];

    final pdf = _buildDocument(primaryFont, fontFallback);
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 9,
      font: primaryFont,
      fontFallback: fontFallback,
    );
    final cellStyle = pw.TextStyle(
      fontSize: 8,
      font: primaryFont,
      fontFallback: fontFallback,
    );
    final titleStyle = pw.TextStyle(
      fontSize: 16,
      fontWeight: pw.FontWeight.bold,
      font: primaryFont,
      fontFallback: fontFallback,
    );

    const rowsPerPage = 30;
    final pageCount = (rows.length / rowsPerPage).ceil().clamp(1, 999);

    for (var page = 0; page < pageCount; page++) {
      final start = page * rowsPerPage;
      final end = (start + rowsPerPage) > rows.length
          ? rows.length
          : start + rowsPerPage;
      final pageRows = rows.sublist(start, end);

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
                headers: headers,
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
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: 0.5,
                ),
                oddRowDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey50,
                ),
                cellAlignments: {
                  for (var i = 0; i < headers.length; i++)
                    i: isRtl
                        ? pw.Alignment.centerRight
                        : pw.Alignment.centerLeft,
                },
              ),
              pw.Spacer(),
              pw.Align(
                alignment: isRtl
                    ? pw.Alignment.centerLeft
                    : pw.Alignment.centerRight,
                child: pw.Text(
                  'Page ${page + 1} of $pageCount',
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
  await _ensureFontBytes();
  final aB = _arabicFontBytes!, uB = _urduFontBytes!;
  return Isolate.run(() {
    final fonts = _fontsFromBytes(aB, uB);
    final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
    final primaryFont = locale == AppLocale.ur ? fonts.urdu : fonts.arabic;
    final ff = locale == AppLocale.ur
        ? <pw.Font>[fonts.arabic]
        : <pw.Font>[fonts.urdu];

    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final align = isRtl
        ? pw.CrossAxisAlignment.end
        : pw.CrossAxisAlignment.start;
    final currencyStr = locale == AppLocale.ar
        ? 'ريال'
        : locale == AppLocale.ur
        ? 'ریال'
        : currency;

    // ── helpers ──
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
      final entryBy = showEntryBy
          ? (entryByMap[tx.createdBy] ?? tx.createdBy)
          : '';

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
    const rowsPerPage = 28;
    final pageCount = ((rows.length + 1) / rowsPerPage).ceil().clamp(1, 999);

    final now = DateTime.now();
    for (var page = 0; page < pageCount; page++) {
      final start = page * rowsPerPage;
      final isFirst = page == 0;
      final isLast = page == pageCount - 1;
      final pageRows = rows.skip(start).take(rowsPerPage).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          textDirection: dir,
          build: (ctx) => pw.Column(
            crossAxisAlignment: align,
            children: [
              if (isFirst) ...[
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
                              labels['account_statement'] ??
                                  'Account Statement',
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
                        color: balance > 0
                            ? PdfColors.red800
                            : PdfColors.green800,
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
              if (!isFirst)
                _buildLedgerHeaderRow(
                  headerLabels,
                  colWidths,
                  colCount,
                  dir,
                  primaryFont,
                  ff,
                ),

              // ── Data rows ──
              ...pageRows.asMap().entries.map((e) {
                final i = e.key;
                final r = e.value;
                final bg = i % 2 == 0 ? PdfColors.white : PdfColors.grey50;
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

              // ── Final balance row (last page) ──
              if (isLast)
                pw.Container(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blue50,
                    border: pw.Border(
                      left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                      right: pw.BorderSide(
                        color: PdfColors.grey400,
                        width: 0.5,
                      ),
                      bottom: pw.BorderSide(
                        color: PdfColors.grey400,
                        width: 0.5,
                      ),
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
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 5,
                        ),
                        child: pw.Text(
                          _fmtAmtC(balance, currencyStr),
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
              pw.Spacer(),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${labels['page'] ?? 'Page'} ${page + 1} / $pageCount',
                  style: ts(size: 7, color: PdfColors.grey500),
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
class SellerReportCustomer {
  final String name;
  final int totalPairsSold;
  final double totalRevenue;
  final double outstandingBalance;
  const SellerReportCustomer({
    required this.name,
    required this.totalPairsSold,
    required this.totalRevenue,
    required this.outstandingBalance,
  });
}

/// Builds a seller summary report PDF.
///
/// [sellerName], [sellerPhone], [routeName] describe the seller.
/// [customers] is the list of summarised customer rows.
/// [stockReceived], [stockSold], [stockRemaining] are in pairs.
Future<Uint8List> buildPdfSellerReport({
  required String sellerName,
  required String sellerPhone,
  required String routeName,
  required List<SellerReportCustomer> customers,
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
  return Isolate.run(() {
    final fonts = _fontsFromBytes(aB, uB);
    final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;

    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    pw.TextStyle ts({
      double size = 9,
      pw.FontWeight fw = pw.FontWeight.normal,
      PdfColor color = PdfColors.black,
    }) => pw.TextStyle(
      fontSize: size,
      fontWeight: fw,
      color: color,
      font: locale == AppLocale.ur ? fonts.urdu : fonts.arabic,
      fontFallback: locale == AppLocale.ur
          ? <pw.Font>[fonts.arabic]
          : <pw.Font>[fonts.urdu],
    );

    double totalRevenue = 0;
    double totalOutstanding = 0;
    int totalPairs = 0;
    for (final c in customers) {
      totalRevenue += c.totalRevenue;
      totalOutstanding += c.outstandingBalance;
      totalPairs += c.totalPairsSold;
    }

    final pdf = _buildDocument(
      locale == AppLocale.ur ? fonts.urdu : fonts.arabic,
      locale == AppLocale.ur ? <pw.Font>[fonts.arabic] : <pw.Font>[fonts.urdu],
    );

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
                        _s(companyName), // ISSUE-015: was hardcoded 'FOOTWEAR'
                        style: ts(size: 18, fw: pw.FontWeight.bold),
                        textDirection: dir,
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
                      textDirection: dir,
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
                  textDirection: dir,
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
                primaryFont: locale == AppLocale.ur ? fonts.urdu : fonts.arabic,
                ff: locale == AppLocale.ur
                    ? <pw.Font>[fonts.arabic]
                    : <pw.Font>[fonts.urdu],
              ),
              pw.SizedBox(width: 8),
              _stockCard(
                labels['stock_sold'] ?? 'Sold',
                stockSold.toString(),
                PdfColors.orange50,
                primaryFont: locale == AppLocale.ur ? fonts.urdu : fonts.arabic,
                ff: locale == AppLocale.ur
                    ? <pw.Font>[fonts.arabic]
                    : <pw.Font>[fonts.urdu],
              ),
              pw.SizedBox(width: 8),
              _stockCard(
                labels['stock_remaining'] ?? 'Remaining',
                stockRemaining.toString(),
                PdfColors.green50,
                primaryFont: locale == AppLocale.ur ? fonts.urdu : fonts.arabic,
                ff: locale == AppLocale.ur
                    ? <pw.Font>[fonts.arabic]
                    : <pw.Font>[fonts.urdu],
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ── Customer Table ──
          pw.Text(
            labels['customers'] ?? 'Customers',
            style: ts(size: 11, fw: pw.FontWeight.bold),
            textDirection: dir,
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: [
              labels['customer'] ?? 'Customer',
              labels['stock_sold'] ?? 'Sold (Pairs)',
              labels['revenue'] ?? 'Revenue',
              labels['outstanding'] ?? 'Outstanding',
            ],
            data: customers
                .map(
                  (c) => [
                    _s(c.name),
                    c.totalPairsSold.toString(),
                    _fmtAmt(c.totalRevenue),
                    _fmtAmt(c.outstandingBalance),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              font: locale == AppLocale.ur ? fonts.urdu : fonts.arabic,
              fontFallback: locale == AppLocale.ur
                  ? <pw.Font>[fonts.arabic]
                  : <pw.Font>[fonts.urdu],
            ),
            cellStyle: pw.TextStyle(
              fontSize: 8,
              font: locale == AppLocale.ur ? fonts.urdu : fonts.arabic,
              fontFallback: locale == AppLocale.ur
                  ? <pw.Font>[fonts.arabic]
                  : <pw.Font>[fonts.urdu],
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
            cellHeight: 22,
            headerDirection: dir,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
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
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              font: primaryFont,
              fontFallback: ff,
            ),
          ),
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7,
              color: PdfColors.grey700,
              font: primaryFont,
              fontFallback: ff,
            ),
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
  return Isolate.run(() {
    final fonts = _fontsFromBytes(aB, uB);
    final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
    final primaryFont = locale == AppLocale.ur ? fonts.urdu : fonts.arabic;
    final ff = locale == AppLocale.ur
        ? <pw.Font>[fonts.arabic]
        : <pw.Font>[fonts.urdu];

    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final align = isRtl
        ? pw.CrossAxisAlignment.end
        : pw.CrossAxisAlignment.start;

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

    final currencyLabel = locale == AppLocale.ar
        ? 'ريال'
        : locale == AppLocale.ur
        ? 'ریال'
        : '﷼';

    final date = invoice.createdAt.toDate();
    final dateStr = _fmtDate(date);
    final isCreditNote = invoice.type != InvoiceModel.typeSale;
    final docTitle = isCreditNote ? 'CREDIT NOTE' : 'INVOICE';

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
                      'Date: $dateStr',
                      style: ts(size: 9, color: PdfColors.grey700),
                      textDirection: dir,
                    ),
                    if (invoice.status == 'void')
                      pw.Text(
                        'VOID',
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
                    'Customer: ${_s(invoice.shopName)}',
                    style: ts(size: 10, fw: pw.FontWeight.bold),
                    textDirection: _cellDir(invoice.shopName, dir),
                  ),
                  if (invoice.shopName.isNotEmpty)
                    pw.Text(
                      'Shop: ${_s(invoice.shopName)}',
                      style: ts(size: 9),
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
                        ['Item', 'Size', 'Color', 'Qty', 'Unit Price', 'Total']
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
                        pw.Text(lblSubtotal, style: ts(size: 9)),
                        pw.Text(_fmtAmt(invoice.subtotal), style: ts(size: 9)),
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
                          ),
                          pw.Text(
                            '-${_fmtAmt(invoice.discount)}',
                            style: ts(size: 9, color: PdfColors.green700),
                          ),
                        ],
                      ),
                    ],
                    pw.Divider(thickness: 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total $currencyLabel',
                          style: ts(size: 11, fw: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          _fmtAmt(invoice.total),
                          style: ts(size: 11, fw: pw.FontWeight.bold),
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
                'Reference: ${_s(invoice.linkedInvoiceId!)}', // ISSUE-036
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
  return Isolate.run(() {
    final fonts = _fontsFromBytes(aB, uB);
    final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
    final primaryFont = locale == AppLocale.ur ? fonts.urdu : fonts.arabic;
    final ff = locale == AppLocale.ur
        ? <pw.Font>[fonts.arabic]
        : <pw.Font>[fonts.urdu];
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final align = isRtl
        ? pw.CrossAxisAlignment.end
        : pw.CrossAxisAlignment.start;
    final currencyStr = locale == AppLocale.ar
        ? 'ريال'
        : locale == AppLocale.ur
        ? 'ریال'
        : currency;

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

    final pdf = _buildDocument(primaryFont, ff);
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
        if (tx.isCashOut) {
          bal += tx.amount;
          tOut += tx.amount;
        } else {
          bal -= tx.amount;
          tIn += tx.amount;
        }
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
              // Cover index table rows
              ...pageRows.asMap().entries.map((e) {
                final gi = pageIdxBase + e.key;
                final sec = e.value;
                final finalBal = sectionFinals[gi];
                final tIn = sectionTotalIn[gi];
                final tOut = sectionTotalOut[gi];
                final bg = e.key % 2 == 0 ? PdfColors.white : PdfColors.grey50;
                return pw.Container(
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
                );
              }),
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

    // ── Per-shop section pages ───────────────────────────────────────────────
    String? lastRouteLabel;
    for (var si = 0; si < sections.length; si++) {
      final sec = sections[si];
      final routeChanged = sec.routeLabel != lastRouteLabel;
      final finalBal = sectionFinals[si];
      final tIn = sectionTotalIn[si];
      final tOut = sectionTotalOut[si];

      // Build ledger rows for this shop
      var balance = sec.openingBalance;
      final sortedTx = [...sec.transactions]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final entryCount = sortedTx.length;
      final rows = <_LedgerRow>[];

      if (sec.openingBalance != 0) {
        rows.add(
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
            : (tx.hasItems
                  ? tx.items.map((i) => _s(i.productName)).join(', ')
                  : '');
        final desc = tx.invoiceNumber != null && tx.invoiceNumber!.isNotEmpty
            ? '[${_s(tx.invoiceNumber!)}] $rawDesc'
            : rawDesc;
        final entryBy = showEntryBy
            ? (entryByMap[tx.createdBy] ?? tx.createdBy)
            : '';
        final mode = tx.saleType ?? '';
        if (tx.isCashOut) {
          balance += tx.amount;
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

      const rowsPerPage = 25;
      final shopPageCount = rows.isEmpty
          ? 1
          : ((rows.length / rowsPerPage).ceil());

      for (var page = 0; page < shopPageCount; page++) {
        final isFirstPage = page == 0;
        final isLastPage = page == shopPageCount - 1;
        final rowStart = page * rowsPerPage;
        final pageDataRows = rows.skip(rowStart).take(rowsPerPage).toList();
        final showRouteBanner = isFirstPage && routeChanged;
        // Capture in local vars for closure safety
        final capturedRoute = sec.routeLabel;
        final capturedShop = sec.shopName;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            textDirection: dir,
            build: (ctx) => pw.Column(
              crossAxisAlignment: align,
              children: [
                if (isFirstPage) ...[
                  if (showRouteBanner)
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
                        _s(capturedRoute),
                        style: ts(
                          size: 10,
                          fw: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                        textDirection: _cellDir(capturedRoute, dir),
                      ),
                    ),
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
                          _s(capturedShop),
                          style: ts(size: 12, fw: pw.FontWeight.bold),
                          textDirection: _cellDir(capturedShop, dir),
                        ),
                        pw.Text(
                          '${labels['report_date'] ?? 'Date'}: ${_fmtDate(now)}'
                          '  |  ${labels['generated_by'] ?? 'By'}: ${_s(generatedBy)}',
                          style: ts(size: 7, color: PdfColors.grey700),
                          textDirection: dir,
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.blue100,
                        width: 0.5,
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      children: [
                        _summaryCell(
                          label: labels['cash_in'] ?? 'Cash In',
                          value: _fmtAmtC(tIn, currencyStr),
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
                          label: labels['cash_out'] ?? 'Cash Out',
                          value: _fmtAmtC(tOut, currencyStr),
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
                          label: labels['net_payable'] ?? 'Balance',
                          value: _fmtAmtC(finalBal.abs(), currencyStr),
                          color: finalBal >= 0
                              ? PdfColors.red800
                              : PdfColors.green800,
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
                  pw.SizedBox(height: 6),
                  _buildLedgerHeaderRow(
                    headerLabels,
                    colWidths,
                    colCount,
                    dir,
                    primaryFont,
                    ff,
                  ),
                ],
                if (!isFirstPage) ...[
                  pw.Container(
                    width: double.infinity,
                    margin: const pw.EdgeInsets.only(bottom: 4),
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                    child: pw.Text(
                      '${_s(capturedShop)} (cont.)',
                      style: ts(size: 9, fw: pw.FontWeight.bold),
                      textDirection: _cellDir(capturedShop, dir),
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
                ...pageDataRows.asMap().entries.map((e) {
                  final bg = e.key % 2 == 0
                      ? PdfColors.white
                      : PdfColors.grey50;
                  return _buildLedgerDataRow(
                    e.value,
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
                if (isLastPage)
                  pw.Container(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue50,
                      border: pw.Border(
                        left: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                        right: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
                        bottom: pw.BorderSide(
                          color: PdfColors.grey400,
                          width: 0.5,
                        ),
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
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 5,
                          ),
                          child: pw.Text(
                            _fmtAmtC(finalBal, currencyStr),
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
                pw.Spacer(),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '${_s(capturedShop)} — ${labels['page'] ?? 'Page'} ${page + 1} / $shopPageCount',
                    style: ts(size: 7, color: PdfColors.grey500),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      lastRouteLabel = sec.routeLabel;
    }

    return pdf.save();
  }); // Isolate.run
}
