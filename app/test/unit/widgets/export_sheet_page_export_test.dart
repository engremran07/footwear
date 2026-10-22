import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/l10n/app_locale.dart';
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
      rasterizer: (pdfBytes, {dpi = 300}) async {
        expect(pdfBytes, isNotEmpty);
        expect(dpi, equals(200));
        return [pageOne, pageTwo];
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
      rasterizer: (sourcePdf, {dpi = 300}) async {
        expect(sourcePdf, same(pdfBytes));
        expect(String.fromCharCodes(sourcePdf.take(5)), '%PDF-');
        expect(dpi, 300);
        return [pagePng];
      },
    );

    expect(exportedPages, hasLength(1));
    expect(exportedPages.single, isNotEmpty);
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
