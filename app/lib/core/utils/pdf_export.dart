import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a PDF document from tabular data and returns bytes.
/// Mirrors the `exportToExcel` API for consistency.
Future<Uint8List> buildPdfTable({
  required String title,
  required List<String> headers,
  required List<List<dynamic>> rows,
  String? subtitle,
}) async {
  final pdf = pw.Document();
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9);
  const cellStyle = pw.TextStyle(fontSize: 8);
  final titleStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);

  // Split rows into pages of ~30 rows each to avoid overflow
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
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (page == 0) ...[
              pw.Text(title, style: titleStyle),
              if (subtitle != null)
                pw.Text(subtitle,
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey700)),
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
              cellAlignments: {
                for (var i = 0; i < headers.length; i++)
                  i: pw.Alignment.centerLeft
              },
            ),
            pw.Spacer(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
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
