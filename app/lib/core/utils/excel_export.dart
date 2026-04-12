import 'package:archive/archive.dart';
import 'download_helper.dart';

// Custom minimal xlsx writer — no dependency on the `excel` package.
// The `excel` package locked `archive` to ^3.x which blocked `image` from
// upgrading to >=4.6.0 (the version that cleans up Wasm build failures).
// This writer produces a fully compliant .xlsx file using archive ^4.x directly.
//
// Supported features:
//   • Styled header row: Arial bold, blue bg (#1565C0), white text, thin borders
//   • Data rows: Arial, thin borders, LTR or RTL alignment
//   • Number cells right-aligned; text cells honour isRtl
//   • Formula-injection guard on cell values (S-08)
//   • Sheet name sanitised (31-char Excel limit, illegal chars stripped)

/// Builds a styled Excel workbook and returns raw bytes, or null on failure.
/// Headers have a blue background with white bold text and thin borders.
/// All data cells have thin borders and correct RTL alignment when [isRtl].
List<int>? buildStyledExcelBytes({
  required String sheetName,
  required List<String> headers,
  required List<List<dynamic>> rows,
  bool isRtl = false,
}) {
  try {
    final safe = _safeSheetName(sheetName);
    final files = {
      '[Content_Types].xml': _contentTypes(),
      '_rels/.rels': _rootRels(),
      'xl/workbook.xml': _workbook(safe),
      'xl/_rels/workbook.xml.rels': _workbookRels(),
      'xl/styles.xml': _styles(isRtl),
      'xl/worksheets/sheet1.xml': _worksheet(headers, rows, isRtl),
    };
    final archive = Archive();
    for (final e in files.entries) {
      archive.addFile(ArchiveFile.string(e.key, e.value));
    }
    return ZipEncoder().encode(archive);
  } catch (_) {
    return null;
  }
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

// ─── helpers ────────────────────────────────────────────────────────────────

String _safeSheetName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\\/*?:\[\]]'), '_').trim();
  if (cleaned.isEmpty) return 'Report';
  return cleaned.length > 31 ? cleaned.substring(0, 31) : cleaned;
}

String _safeExcelText(String raw) {
  if (raw.isEmpty) return raw;
  const dangerousPrefixes = ['=', '+', '-', '@'];
  if (dangerousPrefixes.contains(raw[0])) return "'$raw";
  return raw;
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Converts 0-based column index to Excel letter reference (0→A, 25→Z, 26→AA).
String _colRef(int col) {
  var s = '';
  var c = col;
  while (c >= 0) {
    s = String.fromCharCode(65 + (c % 26)) + s;
    c = c ~/ 26 - 1;
  }
  return s;
}

// ─── xlsx XML builders ───────────────────────────────────────────────────────

String _contentTypes() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';

String _rootRels() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(String sheetName) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets>'
    '<sheet name="${_xmlEscape(sheetName)}" sheetId="1" r:id="rId1"/>'
    '</sheets>'
    '</workbook>';

String _workbookRels() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

String _styles(bool isRtl) {
  final headerAlign = isRtl ? 'right' : 'center';
  final dataAlign = isRtl ? 'right' : 'left';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2">'
      '<font><sz val="11"/><name val="Arial"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>'
      '</fonts>'
      '<fills count="3">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF1565C0"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/></border>'
      '<border>'
      '<left style="thin"/><right style="thin"/>'
      '<top style="thin"/><bottom style="thin"/>'
      '</border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="4">'
      '<xf xfId="0" fontId="0" fillId="0" borderId="0"/>'
      '<xf xfId="0" fontId="1" fillId="2" borderId="1"'
      ' applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="$headerAlign"/></xf>'
      '<xf xfId="0" fontId="0" fillId="0" borderId="1"'
      ' applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="$dataAlign"/></xf>'
      '<xf xfId="0" fontId="0" fillId="0" borderId="1"'
      ' applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="right"/></xf>'
      '</cellXfs>'
      '</styleSheet>';
}

String _worksheet(List<String> headers, List<List<dynamic>> rows, bool isRtl) {
  final buf =
      StringBuffer()
        ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        ..write(
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
        )
        ..write('<sheetViews>')
        ..write(
          '<sheetView workbookViewId="0"${isRtl ? ' rightToLeft="1"' : ''}/>',
        )
        ..write('</sheetViews>')
        ..write('<sheetData>');

  // Header row (Excel row 1)
  buf.write('<row r="1">');
  for (var col = 0; col < headers.length; col++) {
    final ref = '${_colRef(col)}1';
    final text = _xmlEscape(_safeExcelText(headers[col]));
    buf.write('<c r="$ref" t="inlineStr" s="1"><is><t>$text</t></is></c>');
  }
  buf.write('</row>');

  // Data rows (Excel rows 2+)
  for (var rowIdx = 0; rowIdx < rows.length; rowIdx++) {
    final rowNum = rowIdx + 2;
    buf.write('<row r="$rowNum">');
    for (var col = 0; col < rows[rowIdx].length; col++) {
      final ref = '${_colRef(col)}$rowNum';
      final val = rows[rowIdx][col];
      if (val is num) {
        buf.write('<c r="$ref" s="3"><v>$val</v></c>');
      } else {
        final text = _xmlEscape(_safeExcelText(val?.toString() ?? ''));
        buf.write('<c r="$ref" t="inlineStr" s="2"><is><t>$text</t></is></c>');
      }
    }
    buf.write('</row>');
  }

  buf.write('</sheetData></worksheet>');
  return buf.toString();
}
