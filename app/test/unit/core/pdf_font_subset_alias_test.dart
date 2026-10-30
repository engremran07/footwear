// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:typed_data';

import 'package:bidi/bidi.dart' as bidi;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/src/pdf/font/arabic.dart' as arabic;
import 'package:pdf/src/pdf/font/ttf_parser.dart';
import 'package:pdf/src/pdf/font/ttf_writer.dart';

void main() {
  late TtfParser sourceFont;

  setUpAll(() {
    final fontBytes = File('assets/fonts/NotoSansArabic.ttf').readAsBytesSync();
    sourceFont = TtfParser(ByteData.view(fontBytes.buffer));
  });

  List<int> corruptedCodePoints(Iterable<String> lines) {
    final characters = <int>[0];
    for (final line in lines) {
      for (final rune in line.runes) {
        if (!characters.contains(rune)) characters.add(rune);
      }
    }

    final subset = TtfWriter(sourceFont).withChars(characters);
    final embeddedFont = TtfParser(ByteData.view(subset.buffer));
    final corrupted = <int>[];
    for (var index = 1; index < characters.length; index++) {
      final codePoint = characters[index];
      final sourceGlyphIndex = sourceFont.charToGlyphIndexMap[codePoint];
      if (sourceGlyphIndex == null || codePoint == 0x20) continue;

      final expected = sourceFont.readGlyph(sourceGlyphIndex).data;
      final actual = embeddedFont.readGlyph(index).data;
      final bytesToCompare = expected.length < 10 ? expected.length : 10;
      if (actual.length < bytesToCompare) {
        corrupted.add(codePoint);
        continue;
      }
      for (var byte = 0; byte < bytesToCompare; byte++) {
        if (expected[byte] != actual[byte]) {
          corrupted.add(codePoint);
          break;
        }
      }
    }
    return corrupted;
  }

  String shapeRtl(String text) => arabic.convert(text);

  String shapeLtrFirst(String text) =>
      String.fromCharCodes(bidi.logicalToVisual(text));

  test('preserves glyph aliases shared by Arabic and Urdu Yeh forms', () {
    expect(
      corruptedCodePoints([
        shapeRtl('بيت جميل'),
        shapeRtl('نیا'),
        shapeRtl('يوم'),
        shapeRtl('یار'),
        shapeRtl('علی'),
        shapeRtl('على'),
      ]),
      isEmpty,
    );
  });

  test('preserves Arabic glyphs used by both RTL and LTR-first text', () {
    const arabicText = 'تاريخ جاويد';
    final mixedDirectionDocument = [
      shapeRtl(arabicText),
      shapeLtrFirst('Person: $arabicText'),
    ];

    expect(corruptedCodePoints(mixedDirectionDocument), isEmpty);
    expect(corruptedCodePoints(mixedDirectionDocument.reversed), isEmpty);
  });

  test('preserves aliases across realistic Arabic and Urdu report content', () {
    expect(
      corruptedCodePoints([
        shapeRtl('فاتورة مبيعات'),
        shapeLtrFirst('Customer: محمد علی'),
        shapeRtl('نیا کپڑا بیت'),
        shapeLtrFirst('Route: جميل بيت'),
      ]),
      isEmpty,
    );
  });

  test('preserves every Arabic-script letter in each joining position', () {
    final lines = <String>[];
    void addThroughBothShapingPaths(String text) {
      lines.add(shapeRtl(text));
      try {
        lines.add(shapeLtrFirst(text));
      } on RangeError {
        // bidi 2.0.13 does not accept every Arabic-script code point.
      }
    }

    for (final (first, last) in [(0x0621, 0x064A), (0x066E, 0x06D3)]) {
      for (var codePoint = first; codePoint <= last; codePoint++) {
        final letter = String.fromCharCode(codePoint);
        addThroughBothShapingPaths('ب$letterب');
        addThroughBothShapingPaths('ب$letter');
        addThroughBothShapingPaths('$letterب');
        addThroughBothShapingPaths(letter);
      }
    }

    expect(corruptedCodePoints(lines), isEmpty);
  });
}
