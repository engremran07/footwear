import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
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
