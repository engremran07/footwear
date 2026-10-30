import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
import 'package:footwear_erp/core/l10n/financial_document_localization.dart';
import 'package:footwear_erp/core/utils/pdf_export.dart';
import 'package:footwear_erp/widgets/export_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rasterizePdfPagesToPngs preserves one image per PDF page', () async {
    final pageOne = await _makeTestPng(1, 1);
    final pageTwo = await _makeTestPng(1, 1);

    final pageImages = await rasterizePdfPagesToPngs(
      Uint8List.fromList([1, 2, 3]),
      dpi: 200,
      rasterizer: (pdfBytes, {dpi = 300}) async* {
        expect(pdfBytes, isNotEmpty);
        expect(dpi, equals(200));
        yield pageOne;
        yield pageTwo;
      },
    );

    expect(pageImages, hasLength(2));
    for (final imageBytes in pageImages) {
      expect(imageBytes, isNotEmpty);
    }
  });

  test('RTL PDF bytes are passed to the PNG page export path', () async {
    expect(const bool.fromEnvironment('use_arabic'), isTrue);
    final pdfBytes = await buildPdfTable(
      title: 'تقرير اردو',
      headers: const ['دکان'],
      rows: const [
        ['یہ اردو دکان ہے'],
      ],
      locale: AppLocale.ur,
    );
    final pagePng = await _makeTestPng(1, 1);
    final exportedPages = await rasterizePdfPagesToPngs(
      pdfBytes,
      rasterizer: (sourcePdf, {dpi = 300}) async* {
        expect(sourcePdf, same(pdfBytes));
        expect(String.fromCharCodes(sourcePdf.take(5)), '%PDF-');
        expect(dpi, 300);
        yield pagePng;
      },
    );

    expect(exportedPages, hasLength(1));
    expect(exportedPages.single, isNotEmpty);
  });

  testWidgets('export sheet passes the selected language to the PDF builder', (
    tester,
  ) async {
    FinancialDocumentLanguagePair? receivedPair;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => ExportSheet.show(
                  context,
                  ref,
                  title: 'Statement',
                  headers: const [],
                  rows: const [],
                  fileName: 'statement',
                  initialDocumentLanguagePair:
                      FinancialDocumentLanguagePair.englishArabic,
                  pdfBytesBuilderWithLanguagePair: (pair) async {
                    receivedPair = pair;
                    return Uint8List.fromList(const [1, 2, 3]);
                  },
                ),
                child: const Text('Open export'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open export'));
    await tester.pumpAndSettle();
    final selector = find.byKey(
      const ValueKey('export_document_language_selector'),
    );
    expect(selector, findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<FinancialDocumentLanguagePair>>(selector)
          .selected,
      {FinancialDocumentLanguagePair.englishArabic},
    );

    await tester.tap(find.text('Urdu'));
    await tester.pump();
    expect(
      tester
          .widget<SegmentedButton<FinancialDocumentLanguagePair>>(selector)
          .selected,
      {FinancialDocumentLanguagePair.englishUrdu},
    );

    await tester.tap(find.byKey(const ValueKey('export_share_pdf')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(receivedPair, FinancialDocumentLanguagePair.englishUrdu);
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _makeTestPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
