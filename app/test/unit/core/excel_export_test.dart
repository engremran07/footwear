import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/excel_export.dart';

void main() {
  group('buildStyledExcelBytes', () {
    test('returns a non-empty workbook payload', () {
      final bytes = buildStyledExcelBytes(
        sheetName: 'Audit',
        headers: const ['Name', 'Amount'],
        rows: const [
          ['Shop A', 100.0],
        ],
      );

      expect(bytes, isNotNull);
      expect(bytes, isNotEmpty);
    });

    test('preserves Arabic and Urdu text in an RTL worksheet', () {
      final bytes = buildStyledExcelBytes(
        sheetName: 'تقرير الحساب',
        headers: const ['المتجر', 'دکان'],
        rows: const [
          ['شركة الأحذية', 'یہ اردو رپورٹ ٹ ڈ ڑ ں ھ ے'],
        ],
        isRtl: true,
      );

      final archive = ZipDecoder().decodeBytes(bytes!);
      final sheet = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
      );
      final workbook = utf8.decode(
        archive.findFile('xl/workbook.xml')!.content as List<int>,
      );

      expect(sheet, contains('rightToLeft="1"'));
      expect(sheet, contains('شركة الأحذية'));
      expect(sheet, contains('یہ اردو رپورٹ ٹ ڈ ڑ ں ھ ے'));
      expect(workbook, contains('تقرير الحساب'));
    });

    test('guards against formula injection after trimming leading spaces', () {
      final bytes = buildStyledExcelBytes(
        sheetName: 'Audit',
        headers: const ['Name'],
        rows: const [
          ['  =SUM(A1:A2)'],
        ],
      );

      final archive = ZipDecoder().decodeBytes(bytes!);
      final sheet = archive.findFile('xl/worksheets/sheet1.xml');
      final xml = utf8.decode(sheet!.content as List<int>);

      expect(xml, contains('&apos;=SUM(A1:A2)'));
      expect(xml, isNot(contains('&gt;  =SUM(A1:A2)&lt;')));
    });
  });
}
