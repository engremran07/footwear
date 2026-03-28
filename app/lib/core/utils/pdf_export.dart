import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../l10n/app_locale.dart';
import '../../models/transaction_model.dart';

/// Cached font data so we don't reload from assets on every export.
pw.Font? _cachedArabicFont;
pw.Font? _cachedUrduFont;

Future<pw.Font> _loadArabicFont() async {
  if (_cachedArabicFont != null) return _cachedArabicFont!;
  final data = await rootBundle.load('assets/fonts/NotoSansArabic.ttf');
  _cachedArabicFont = pw.Font.ttf(data);
  return _cachedArabicFont!;
}

Future<pw.Font> _loadUrduFont() async {
  if (_cachedUrduFont != null) return _cachedUrduFont!;
  final data = await rootBundle.load('assets/fonts/NotoNastaliqUrdu.ttf');
  _cachedUrduFont = pw.Font.ttf(data);
  return _cachedUrduFont!;
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
}) async {
  final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
  pw.Font? rtlFont;
  if (locale == AppLocale.ar) {
    rtlFont = await _loadArabicFont();
  } else if (locale == AppLocale.ur) {
    rtlFont = await _loadUrduFont();
  }

  // Always include both RTL fonts as fallback so that Arabic/Urdu text in
  // descriptions renders correctly even when the app is in English mode.
  final arabicFont = await _loadArabicFont();
  final urduFont = await _loadUrduFont();
  final fontFallback = <pw.Font>[arabicFont, urduFont];

  final pdf = pw.Document();
  final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  final headerStyle = pw.TextStyle(
    fontWeight: pw.FontWeight.bold,
    fontSize: 9,
    font: rtlFont,
    fontFallback: fontFallback,
  );
  final cellStyle = pw.TextStyle(
    fontSize: 8,
    font: rtlFont,
    fontFallback: fontFallback,
  );
  final titleStyle = pw.TextStyle(
    fontSize: 16,
    fontWeight: pw.FontWeight.bold,
    font: rtlFont,
    fontFallback: fontFallback,
  );

  const rowsPerPage = 30;
  final pageCount = (rows.length / rowsPerPage).ceil().clamp(1, 999);

  for (var page = 0; page < pageCount; page++) {
    final start = page * rowsPerPage;
    final end =
        (start + rowsPerPage) > rows.length ? rows.length : start + rowsPerPage;
    final pageRows = rows.sublist(start, end);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: dir,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment:
              isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
          children: [
            if (page == 0) ...[
              pw.Text(title, style: titleStyle, textDirection: dir),
              if (subtitle != null)
                pw.Text(subtitle,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                      fontFallback: fontFallback,
                    ),
                    textDirection: dir),
              pw.SizedBox(height: 12),
            ],
            pw.TableHelper.fromTextArray(
              context: context,
              headers: headers,
              data: pageRows
                  .map((row) => row.map((c) => c?.toString() ?? '').toList())
                  .toList(),
              headerStyle: headerStyle,
              cellStyle: cellStyle,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
              cellHeight: 22,
              headerDirection: dir,
              cellAlignments: {
                for (var i = 0; i < headers.length; i++)
                  i: isRtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft
              },
            ),
            pw.Spacer(),
            pw.Align(
              alignment:
                  isRtl ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
              child: pw.Text(
                'Page ${page + 1} of $pageCount',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  return pdf.save();
}

// ─────────────────────────────────────────────────────────────────────────────
// CA-grade Account Statement (portrait A4, running balance)
// ─────────────────────────────────────────────────────────────────────────────

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtAmt(double v) => v.toStringAsFixed(2);

/// Builds a CA-grade customer account statement PDF with running balance,
/// summary totals, and optional Entry By column.
///
/// [companyName] and [generatedBy] populate the report header.
/// [entryByMap] maps uid → display name for the Entry By column.
Future<Uint8List> buildPdfLedger({
  required String customerName,
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
}) async {
  final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
  pw.Font? rtlFont;
  if (locale == AppLocale.ar) rtlFont = await _loadArabicFont();
  if (locale == AppLocale.ur) rtlFont = await _loadUrduFont();

  // Always include both RTL fonts as fallback so Arabic/Urdu descriptions
  // render correctly regardless of the active UI locale.
  final arabicFont = await _loadArabicFont();
  final urduFont = await _loadUrduFont();

  final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final align = isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start;
  final ff = <pw.Font>[arabicFont, urduFont];

  // ── helpers ──
  pw.TextStyle ts(
          {double size = 9,
          pw.FontWeight fw = pw.FontWeight.normal,
          PdfColor color = PdfColors.black}) =>
      pw.TextStyle(
          fontSize: size,
          fontWeight: fw,
          color: color,
          font: isRtl ? rtlFont : null,
          fontFallback: ff);

  // ── build ledger rows ──
  double balance = openingBalance;
  double totalCashIn = 0;
  double totalCashOut = 0;
  final int entryCount = transactions.length;

  final rows = <_LedgerRow>[];
  for (final tx in transactions) {
    final date = tx.createdAt.toDate();
    final desc = tx.description?.isNotEmpty == true
        ? tx.description!
        : (tx.hasItems ? tx.items.map((i) => i.productName).join(', ') : '');
    final mode = tx.saleType ?? '';
    final entryBy =
        showEntryBy ? (entryByMap[tx.createdBy] ?? tx.createdBy) : '';

    if (tx.isCashOut) {
      balance += tx.amount;
      totalCashOut += tx.amount;
      rows.add(_LedgerRow(
        date: _fmtDate(date),
        desc: desc,
        entryBy: entryBy,
        mode: mode,
        cashIn: 0,
        cashOut: tx.amount,
        balance: balance,
      ));
    } else {
      balance -= tx.amount;
      totalCashIn += tx.amount;
      rows.add(_LedgerRow(
        date: _fmtDate(date),
        desc: desc,
        entryBy: entryBy,
        mode: mode,
        cashIn: tx.amount,
        cashOut: 0,
        balance: balance,
      ));
    }
  }

  // ── column widths (portrait A4 usable ≈ 539 pt) ──
  const double dateW = 52;
  const double remarkW = 118;
  const double entryByW = 64;
  const double modeW = 50;
  const double amtW = 66;
  const double balW = 68;

  final colWidths = showEntryBy
      ? [dateW, remarkW, entryByW, modeW, amtW, amtW, balW]
      : [dateW, remarkW, modeW, amtW, amtW, balW];
  final headerLabels = showEntryBy
      ? [
          labels['date'] ?? 'Date',
          labels['description'] ?? 'Remark',
          labels['entry_by'] ?? 'Entry By',
          labels['mode'] ?? 'Mode',
          labels['credit'] ?? 'Cash In',
          labels['debit'] ?? 'Cash Out',
          labels['running_balance'] ?? 'Balance',
        ]
      : [
          labels['date'] ?? 'Date',
          labels['description'] ?? 'Remark',
          labels['mode'] ?? 'Mode',
          labels['credit'] ?? 'Cash In',
          labels['debit'] ?? 'Cash Out',
          labels['running_balance'] ?? 'Balance',
        ];
  final colCount = colWidths.length;

  final pdf = pw.Document();
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
                  pw.Column(crossAxisAlignment: align, children: [
                    pw.Text(companyName,
                        style: ts(size: 16, fw: pw.FontWeight.bold),
                        textDirection: dir),
                    pw.Text(labels['account_statement'] ?? 'Account Statement',
                        style: ts(
                            size: 11,
                            fw: pw.FontWeight.bold,
                            color: PdfColors.blue800),
                        textDirection: dir),
                  ]),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                          '${labels['report_date'] ?? 'Generated On'}: ${_fmtDate(now)}',
                          style: ts(size: 8, color: PdfColors.grey700),
                          textDirection: dir),
                      if (generatedBy.isNotEmpty)
                        pw.Text(
                            '${labels['generated_by'] ?? 'By'}: $generatedBy',
                            style: ts(size: 8, color: PdfColors.grey700),
                            textDirection: dir),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.blue800),
              pw.SizedBox(height: 6),
              pw.Text(customerName,
                  style: ts(size: 14, fw: pw.FontWeight.bold),
                  textDirection: dir),
              pw.SizedBox(height: 4),
              if (dateFrom != null && dateTo != null)
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
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
                        value: _fmtAmt(totalCashIn),
                        color: PdfColors.green800,
                        ff: ff),
                    pw.Container(
                        width: 0.5, height: 40, color: PdfColors.blue100),
                    _summaryCell(
                        label: labels['cash_out'] ?? 'Total Cash Out',
                        value: _fmtAmt(totalCashOut),
                        color: PdfColors.red800,
                        ff: ff),
                    pw.Container(
                        width: 0.5, height: 40, color: PdfColors.blue100),
                    _summaryCell(
                        label: labels['net_payable'] ?? 'Final Balance',
                        value: _fmtAmt(balance.abs()),
                        color:
                            balance > 0 ? PdfColors.red800 : PdfColors.green800,
                        ff: ff,
                        isBold: true),
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
              _buildLedgerHeaderRow(headerLabels, colWidths, colCount, dir, ff),
            ],
            if (!isFirst)
              _buildLedgerHeaderRow(headerLabels, colWidths, colCount, dir, ff),

            // ── Data rows ──
            ...pageRows.asMap().entries.map((e) {
              final i = e.key;
              final r = e.value;
              final bg = i % 2 == 0 ? PdfColors.white : PdfColors.grey50;
              return _buildLedgerDataRow(
                  r, colWidths, colCount, bg, dir, ff, showEntryBy);
            }),

            // ── Final balance row (last page) ──
            if (isLast)
              pw.Container(
                color: PdfColors.blue50,
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: colWidths
                          .take(colCount - 1)
                          .fold<double>(0, (a, b) => a + b),
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4, vertical: 5),
                      child: pw.Text(
                        labels['net_payable'] ?? 'Final Balance',
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue800,
                            font: isRtl ? rtlFont : null,
                            fontFallback: ff),
                        textDirection: dir,
                      ),
                    ),
                    pw.Container(
                      width: colWidths.last,
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4, vertical: 5),
                      child: pw.Text(
                        _fmtAmt(balance),
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: balance > 0
                                ? PdfColors.red800
                                : PdfColors.green800,
                            font: isRtl ? rtlFont : null,
                            fontFallback: ff),
                        textDirection: dir,
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
  required List<pw.Font> ff,
  bool isBold = false,
}) {
  final primaryFont = ff.isNotEmpty ? ff.first : null;
  return pw.Expanded(
    child: pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey600,
                  font: primaryFont,
                  fontFallback: ff),
              textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color,
                  font: primaryFont,
                  fontFallback: ff),
              textAlign: pw.TextAlign.center),
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
  List<pw.Font> ff,
) {
  final primaryFont = ff.isNotEmpty ? ff.first : null;
  return pw.Container(
    color: PdfColors.blue800,
    child: pw.Row(
      children: List.generate(count, (i) {
        return pw.Container(
          width: widths[i],
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: pw.Text(
            labels[i],
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                font: primaryFont,
                fontFallback: ff),
            textDirection: dir,
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
  List<pw.Font> ff,
  bool showEntryBy,
) {
  final primaryFont = ff.isNotEmpty ? ff.first : null;
  final cells = showEntryBy
      ? [
          r.date,
          r.desc,
          r.entryBy,
          r.mode,
          r.cashIn > 0 ? _fmtAmt(r.cashIn) : '',
          r.cashOut > 0 ? _fmtAmt(r.cashOut) : '',
          _fmtAmt(r.balance),
        ]
      : [
          r.date,
          r.desc,
          r.mode,
          r.cashIn > 0 ? _fmtAmt(r.cashIn) : '',
          r.cashOut > 0 ? _fmtAmt(r.cashOut) : '',
          _fmtAmt(r.balance),
        ];
  final cashInIdx = showEntryBy ? 4 : 3;
  final cashOutIdx = showEntryBy ? 5 : 4;

  return pw.Container(
    color: bg,
    child: pw.Row(
      children: List.generate(count, (i) {
        PdfColor? color;
        if (i == cashInIdx && r.cashIn > 0) color = PdfColors.green800;
        if (i == cashOutIdx && r.cashOut > 0) color = PdfColors.red800;
        return pw.Container(
          width: widths[i],
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(
            cells[i],
            style: pw.TextStyle(
                fontSize: 8, color: color, font: primaryFont, fontFallback: ff),
            textDirection: dir,
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
}) async {
  final isRtl = locale == AppLocale.ar || locale == AppLocale.ur;
  pw.Font? rtlFont;
  if (locale == AppLocale.ar) rtlFont = await _loadArabicFont();
  if (locale == AppLocale.ur) rtlFont = await _loadUrduFont();

  // Always include both RTL fonts as fallback for mixed-content rendering.
  final arabicFont = await _loadArabicFont();
  final urduFont = await _loadUrduFont();

  final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final ff = <pw.Font>[arabicFont, urduFont];

  pw.TextStyle ts(
          {double size = 9,
          pw.FontWeight fw = pw.FontWeight.normal,
          PdfColor color = PdfColors.black}) =>
      pw.TextStyle(
          fontSize: size,
          fontWeight: fw,
          color: color,
          font: isRtl ? rtlFont : null,
          fontFallback: ff);

  double totalRevenue = 0;
  double totalOutstanding = 0;
  int totalPairs = 0;
  for (final c in customers) {
    totalRevenue += c.totalRevenue;
    totalOutstanding += c.outstandingBalance;
    totalPairs += c.totalPairsSold;
  }

  final pdf = pw.Document();

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
            pw.Column(
                crossAxisAlignment: isRtl
                    ? pw.CrossAxisAlignment.end
                    : pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FOOTWEAR',
                    style: ts(size: 18, fw: pw.FontWeight.bold),
                    textDirection: dir,
                  ),
                  pw.Text(
                    labels['seller_report'] ?? 'Seller Report',
                    style: ts(
                        size: 13,
                        fw: pw.FontWeight.bold,
                        color: PdfColors.blue800),
                    textDirection: dir,
                  ),
                ]),
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
                      '${labels['seller'] ?? 'Seller'}: $sellerName',
                      style: ts(size: 10, fw: pw.FontWeight.bold),
                      textDirection: dir,
                    ),
                    pw.Text(sellerPhone,
                        style: ts(size: 9), textDirection: dir),
                  ]),
              pw.Text(
                '${labels['route'] ?? 'Route'}: $routeName',
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
            _stockCard(labels['stock_received'] ?? 'Received',
                stockReceived.toString(), PdfColors.blue50,
                ff: ff),
            pw.SizedBox(width: 8),
            _stockCard(labels['stock_sold'] ?? 'Sold', stockSold.toString(),
                PdfColors.orange50,
                ff: ff),
            pw.SizedBox(width: 8),
            _stockCard(labels['stock_remaining'] ?? 'Remaining',
                stockRemaining.toString(), PdfColors.green50,
                ff: ff),
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
              .map((c) => [
                    c.name,
                    c.totalPairsSold.toString(),
                    _fmtAmt(c.totalRevenue),
                    _fmtAmt(c.outstandingBalance),
                  ])
              .toList(),
          headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontFallback: ff),
          cellStyle: pw.TextStyle(fontSize: 8, fontFallback: ff),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
          rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
          cellHeight: 22,
          headerDirection: dir,
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
                        : PdfColors.green700),
                textDirection: dir,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _stockCard(String label, String value, PdfColor bg,
    {required List<pw.Font> ff}) {
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
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  fontFallback: ff)),
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 7, color: PdfColors.grey700, fontFallback: ff)),
        ],
      ),
    ),
  );
}
