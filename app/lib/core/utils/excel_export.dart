import 'dart:math' as math;
import 'package:archive/archive.dart';
import 'download_helper.dart';

// Custom minimal xlsx writer — no dependency on the `excel` package.
// The `excel` package locked `archive` to ^3.x which blocked `image` from
// upgrading to >=4.6.0 (the version that cleans up Wasm build failures).
// This writer produces a fully compliant .xlsx file using archive ^4.x directly.
//
// Enterprise features:
//   • Title row: report name, bold 14pt, merged across all columns
//   • Subtitle row: date/time stamp, grey italic 10pt, merged
//   • Styled header row: bold 11pt, branded blue bg (#1565C0), white text, thin borders
//   • Alternating row bands: white / light blue (#E3F2FD) for readability
//   • Number cells right-aligned with 2-decimal format; text cells honour isRtl
//   • Auto-fit column widths based on content (capped at 50 chars)
//   • Freeze panes below header row for scrolling
//   • Formula-injection guard on cell values (S-08)
//   • Sheet name sanitised (31-char Excel limit, illegal chars stripped)
//   • Print area + landscape orientation on large tables

/// Builds a styled Excel workbook and returns raw bytes, or null on failure.
List<int>? buildStyledExcelBytes({
  required String sheetName,
  required List<String> headers,
  required List<List<dynamic>> rows,
  bool isRtl = false,
}) {
  final safe = _safeSheetName(sheetName);
  // Calculate auto-fit column widths from headers + data
  final colWidths = _autoFitWidths(headers, rows);
  final now = DateTime.now();
  final subtitle =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  final files = {
    '[Content_Types].xml': _contentTypes(),
    '_rels/.rels': _rootRels(),
    'xl/workbook.xml': _workbook(safe),
    'xl/_rels/workbook.xml.rels': _workbookRels(),
    'xl/styles.xml': _styles(isRtl),
    'xl/worksheets/sheet1.xml': _worksheet(
      safe,
      subtitle,
      headers,
      rows,
      colWidths,
      isRtl,
    ),
  };
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.string(e.key, e.value));
  }
  return ZipEncoder().encode(archive);
}

/// Builds a styled workbook and triggers a file download / save to device.
Future<void> exportToExcel({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<dynamic>> rows,
  bool isRtl = false,
}) async {
  final bytes = buildStyledExcelBytes(
    sheetName: sheetName,
    headers: headers,
    rows: rows,
    isRtl: isRtl,
  );
  if (bytes == null) throw Exception('format');
  await downloadBytes(bytes, '$fileName.xlsx');
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

/// Auto-fit column widths based on header + data content lengths.
/// Width is in Excel character units (roughly 1 char = 1 unit).
/// Minimum 8, maximum 50.
List<double> _autoFitWidths(
  List<String> headers,
  List<List<dynamic>> rows,
) {
  final widths = List<double>.filled(headers.length, 8.0);
  for (var col = 0; col < headers.length; col++) {
    var maxLen = headers[col].length;
    for (final row in rows) {
      if (col < row.length) {
        final cellLen = (row[col]?.toString() ?? '').length;
        if (cellLen > maxLen) maxLen = cellLen;
      }
    }
    // Add padding (2 chars) and clamp
    widths[col] = math.min(math.max(maxLen + 2, 8), 50).toDouble();
  }
  return widths;
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

// Style indices:
//  0 = default
//  1 = header row (bold white on blue, centred, borders)
//  2 = data text (borders, left/right align)
//  3 = data number (borders, right align, 2-decimal format)
//  4 = title row (bold 14pt, no borders)
//  5 = subtitle row (italic 10pt grey, no borders)
//  6 = data text ALT band (borders, light blue bg)
//  7 = data number ALT band (borders, light blue bg, right, 2-decimal)
String _styles(bool isRtl) {
  final headerAlign = isRtl ? 'right' : 'center';
  final dataAlign = isRtl ? 'right' : 'left';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      // ── numFmts: custom 2-decimal number format ──
      '<numFmts count="1">'
      '<numFmt numFmtId="164" formatCode="#,##0.00"/>'
      '</numFmts>'
      // ── fonts ──
      '<fonts count="5">'
      '<font><sz val="11"/><name val="Calibri"/></font>' // 0: default
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>' // 1: header bold white
      '<font><b/><sz val="14"/><name val="Calibri"/></font>' // 2: title bold 14pt
      '<font><i/><sz val="10"/><color rgb="FF757575"/><name val="Calibri"/></font>' // 3: subtitle italic grey
      '<font><sz val="11"/><name val="Calibri"/></font>' // 4: data (same as 0)
      '</fonts>'
      // ── fills ──
      '<fills count="4">'
      '<fill><patternFill patternType="none"/></fill>' // 0: none
      '<fill><patternFill patternType="gray125"/></fill>' // 1: gray125 (required)
      '<fill><patternFill patternType="solid"><fgColor rgb="FF1565C0"/></patternFill></fill>' // 2: branded blue
      '<fill><patternFill patternType="solid"><fgColor rgb="FFE3F2FD"/></patternFill></fill>' // 3: light blue band
      '</fills>'
      // ── borders ──
      '<borders count="3">'
      '<border><left/><right/><top/><bottom/></border>' // 0: none
      '<border>' // 1: thin all
      '<left style="thin"><color rgb="FFB0BEC5"/></left>'
      '<right style="thin"><color rgb="FFB0BEC5"/></right>'
      '<top style="thin"><color rgb="FFB0BEC5"/></top>'
      '<bottom style="thin"><color rgb="FFB0BEC5"/></bottom>'
      '</border>'
      '<border>' // 2: bottom thick (title separator)
      '<left/><right/><top/>'
      '<bottom style="medium"><color rgb="FF1565C0"/></bottom>'
      '</border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="8">'
      // 0: default
      '<xf xfId="0" fontId="0" fillId="0" borderId="0"/>'
      // 1: header row — bold white on blue, centred, borders
      '<xf xfId="0" fontId="1" fillId="2" borderId="1"'
      ' applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="$headerAlign" vertical="center" wrapText="1"/></xf>'
      // 2: data text — borders, left/right align
      '<xf xfId="0" fontId="0" fillId="0" borderId="1"'
      ' applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="$dataAlign" vertical="center"/></xf>'
      // 3: data number — borders, right align, 2-decimal format
      '<xf xfId="0" fontId="0" fillId="0" borderId="1"'
      ' applyBorder="1" applyAlignment="1" applyNumberFormat="1" numFmtId="164">'
      '<alignment horizontal="right" vertical="center"/></xf>'
      // 4: title row — bold 14pt, bottom border
      '<xf xfId="0" fontId="2" fillId="0" borderId="2"'
      ' applyFont="1" applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="$dataAlign" vertical="center"/></xf>'
      // 5: subtitle row — italic grey 10pt
      '<xf xfId="0" fontId="3" fillId="0" borderId="0"'
      ' applyFont="1" applyAlignment="1">'
      '<alignment horizontal="$dataAlign" vertical="center"/></xf>'
      // 6: data text ALT band — light blue bg
      '<xf xfId="0" fontId="0" fillId="3" borderId="1"'
      ' applyFill="1" applyBorder="1" applyAlignment="1">'
      '<alignment horizontal="$dataAlign" vertical="center"/></xf>'
      // 7: data number ALT band — light blue bg, right, 2-decimal
      '<xf xfId="0" fontId="0" fillId="3" borderId="1"'
      ' applyFill="1" applyBorder="1" applyAlignment="1" applyNumberFormat="1" numFmtId="164">'
      '<alignment horizontal="right" vertical="center"/></xf>'
      '</cellXfs>'
      '</styleSheet>';
}

String _worksheet(
  String title,
  String subtitle,
  List<String> headers,
  List<List<dynamic>> rows,
  List<double> colWidths,
  bool isRtl,
) {
  final colCount = headers.length;
  // Data starts at row 4 (title=1, subtitle=2, blank spacer=3, header=4, data=5+)
  const titleRow = 1;
  const subtitleRow = 2;
  const headerRow = 4;
  const dataStartRow = 5;
  final lastDataRow = dataStartRow + rows.length - 1;
  final lastCol = _colRef(colCount - 1);

  final buf = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
      ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    )
    // ── Sheet views: freeze panes below header, RTL support ──
    ..write('<sheetViews>')
    ..write(
      '<sheetView workbookViewId="0"${isRtl ? ' rightToLeft="1"' : ''}>',
    )
    ..write('<pane ySplit="$headerRow" topLeftCell="A$dataStartRow" activePane="bottomLeft" state="frozen"/>')
    ..write('</sheetView>')
    ..write('</sheetViews>')
    // ── Column widths ──
    ..write('<cols>');
  for (var i = 0; i < colWidths.length; i++) {
    final c = i + 1; // 1-based
    buf.write(
      '<col min="$c" max="$c" width="${colWidths[i].toStringAsFixed(1)}" customWidth="1"/>',
    );
  }
  buf
    ..write('</cols>')
    // ── Merge cells: title and subtitle span all columns ──
    ..write('<sheetData>');

  // Row 1: Title (merged)
  buf.write('<row r="$titleRow" ht="24" customHeight="1">');
  buf.write(
    '<c r="A$titleRow" t="inlineStr" s="4"><is><t>${_xmlEscape(title)}</t></is></c>',
  );
  buf.write('</row>');

  // Row 2: Subtitle (merged)
  buf.write('<row r="$subtitleRow" ht="18" customHeight="1">');
  buf.write(
    '<c r="A$subtitleRow" t="inlineStr" s="5"><is><t>Generated: ${_xmlEscape(subtitle)}</t></is></c>',
  );
  buf.write('</row>');

  // Row 3: blank spacer (skip)

  // Row 4: Header row
  buf.write('<row r="$headerRow" ht="22" customHeight="1">');
  for (var col = 0; col < colCount; col++) {
    final ref = '${_colRef(col)}$headerRow';
    final text = _xmlEscape(_safeExcelText(headers[col]));
    buf.write('<c r="$ref" t="inlineStr" s="1"><is><t>$text</t></is></c>');
  }
  buf.write('</row>');

  // Data rows (starting at row 5)
  for (var rowIdx = 0; rowIdx < rows.length; rowIdx++) {
    final rowNum = dataStartRow + rowIdx;
    final isAlt = rowIdx % 2 == 1; // alternating band
    buf.write('<row r="$rowNum">');
    for (var col = 0; col < rows[rowIdx].length; col++) {
      final ref = '${_colRef(col)}$rowNum';
      final val = rows[rowIdx][col];
      if (val is num) {
        // Number cell — style 3 (white) or 7 (blue band)
        buf.write('<c r="$ref" s="${isAlt ? 7 : 3}"><v>$val</v></c>');
      } else {
        // Text cell — style 2 (white) or 6 (blue band)
        final text = _xmlEscape(_safeExcelText(val?.toString() ?? ''));
        buf.write(
          '<c r="$ref" t="inlineStr" s="${isAlt ? 6 : 2}"><is><t>$text</t></is></c>',
        );
      }
    }
    buf.write('</row>');
  }

  buf.write('</sheetData>');

  // ── Merge cells: title and subtitle across all columns ──
  if (colCount > 1) {
    buf.write('<mergeCells count="2">');
    buf.write('<mergeCell ref="A$titleRow:$lastCol$titleRow"/>');
    buf.write('<mergeCell ref="A$subtitleRow:$lastCol$subtitleRow"/>');
    buf.write('</mergeCells>');
  }

  // ── Print setup: landscape for wide tables, portrait for narrow ──
  if (colCount > 4) {
    buf.write('<pageSetup orientation="landscape"/>');
  }

  // ── Auto-filter on header row for easy filtering ──
  if (rows.isNotEmpty) {
    buf.write(
      '<autoFilter ref="A$headerRow:$lastCol${rows.isEmpty ? headerRow : lastDataRow}"/>',
    );
  }

  buf.write('</worksheet>');
  return buf.toString();
}
