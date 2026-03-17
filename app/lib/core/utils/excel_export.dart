import 'package:excel/excel.dart';
import 'download_helper.dart';

/// Builds an [Excel] workbook with [sheetName] from [headers] + [rows]
/// and triggers a browser download (web) or saves to Downloads (Android).
void exportToExcel({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<dynamic>> rows,
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', sheetName);
  final sheet = excel[sheetName];

  // Header row
  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

  // Data rows
  for (final row in rows) {
    sheet.appendRow(row.map((cell) {
      if (cell == null) return TextCellValue('');
      if (cell is num) return DoubleCellValue(cell.toDouble());
      return TextCellValue(cell.toString());
    }).toList());
  }

  final bytes = excel.encode();
  if (bytes == null) return;
  downloadBytes(bytes, '$fileName.xlsx');
}
