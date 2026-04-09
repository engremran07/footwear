import 'package:excel/excel.dart';
import 'download_helper.dart';

/// Builds a styled Excel workbook and returns raw bytes, or null on failure.
/// Headers have a blue background with white bold text and thin borders.
/// All data cells have thin borders and correct RTL alignment when [isRtl].
List<int>? buildStyledExcelBytes({
  required String sheetName,
  required List<String> headers,
  required List<List<dynamic>> rows,
  bool isRtl = false,
}) {
  final excel = Excel.createExcel();
  final safeSheetName = _safeSheetName(sheetName);
  excel.rename('Sheet1', safeSheetName);
  final sheet = excel[safeSheetName];
  if (isRtl) sheet.isRTL = true;

  _writeStyledSheet(sheet, headers: headers, rows: rows, isRtl: isRtl);
  return excel.encode();
}

String _safeSheetName(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/*?:\[\]]'), '_')
      .trim();
  if (cleaned.isEmpty) return 'Report';
  return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
}

String _safeExcelText(String raw) {
  if (raw.isEmpty) return raw;
  const dangerousPrefixes = ['=', '+', '-', '@'];
  final first = raw[0];
  if (dangerousPrefixes.contains(first)) return "'$raw";
  return raw;
}

/// Builds a styled workbook and triggers a file download / save to device.
void exportToExcel({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<dynamic>> rows,
  bool isRtl = false,
}) {
  final bytes = buildStyledExcelBytes(
    sheetName: sheetName,
    headers: headers,
    rows: rows,
    isRtl: isRtl,
  );
  if (bytes == null) return;
  downloadBytes(bytes, '$fileName.xlsx');
}

void _writeStyledSheet(
  Sheet sheet, {
  required List<String> headers,
  required List<List<dynamic>> rows,
  bool isRtl = false,
}) {
  final thinBorder = Border(borderStyle: BorderStyle.Thin);

  final headerStyle = CellStyle(
    bold: true,
    fontFamily: 'Arial',
    fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('FF1565C0'),
    horizontalAlign: isRtl ? HorizontalAlign.Right : HorizontalAlign.Center,
    topBorder: thinBorder,
    bottomBorder: thinBorder,
    leftBorder: thinBorder,
    rightBorder: thinBorder,
  );
  final dataStyle = CellStyle(
    fontFamily: 'Arial',
    horizontalAlign: isRtl ? HorizontalAlign.Right : HorizontalAlign.Left,
    topBorder: thinBorder,
    bottomBorder: thinBorder,
    leftBorder: thinBorder,
    rightBorder: thinBorder,
  );
  final numStyle = CellStyle(
    fontFamily: 'Arial',
    horizontalAlign: HorizontalAlign.Right,
    topBorder: thinBorder,
    bottomBorder: thinBorder,
    leftBorder: thinBorder,
    rightBorder: thinBorder,
  );

  // Header row
  for (var col = 0; col < headers.length; col++) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
    cell.value = TextCellValue(headers[col]);
    cell.cellStyle = headerStyle;
  }

  // Data rows
  for (var rowIdx = 0; rowIdx < rows.length; rowIdx++) {
    final row = rows[rowIdx];
    for (var col = 0; col < row.length; col++) {
      final rawVal = row[col];
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx + 1));
      if (rawVal == null) {
        cell.value = TextCellValue('');
        cell.cellStyle = dataStyle;
      } else if (rawVal is num) {
        cell.value = DoubleCellValue(rawVal.toDouble());
        cell.cellStyle = numStyle;
      } else {
        cell.value = TextCellValue(_safeExcelText(rawVal.toString()));
        cell.cellStyle = dataStyle;
      }
    }
  }
}
