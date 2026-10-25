import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:footwear_erp/core/utils/workspace_logo_processor.dart';
import 'package:footwear_erp/models/settings_model.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'resizes proportionally, preserves alpha, and measures Base64 output',
    () async {
      final source = image.Image(width: 1200, height: 600, numChannels: 4);
      image.fill(source, color: image.ColorRgba8(40, 80, 120, 96));

      final processed = await WorkspaceLogoProcessor.process(
        Uint8List.fromList(image.encodePng(source)),
      );
      final decoded = image.decodeImage(processed.pngBytes)!;

      expect(processed.width, 800);
      expect(processed.height, 400);
      expect(processed.sourceWidth, 1200);
      expect(processed.sourceHeight, 600);
      expect(
        processed.base64.length,
        lessThanOrEqualTo(SettingsModel.maxLogoBase64Bytes),
      );
      expect(decoded.getPixel(0, 0).a, closeTo(96, 1));
    },
  );

  test('rejects files that cannot be decoded as an image', () async {
    await expectLater(
      WorkspaceLogoProcessor.process(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(
        isA<WorkspaceLogoProcessingException>().having(
          (error) => error.code,
          'code',
          'settings_logo_invalid_image',
        ),
      ),
    );
  });

  test(
    'automatically resizes detailed PNGs to the Base64 storage cap',
    () async {
      final random = Random(17);
      final source = image.Image(width: 400, height: 400, numChannels: 4);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgba(
            x,
            y,
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
            255,
          );
        }
      }

      final processed = await WorkspaceLogoProcessor.process(
        Uint8List.fromList(image.encodePng(source)),
      );
      final decoded = image.decodeImage(processed.pngBytes)!;

      expect(processed.sourceWidth, 400);
      expect(processed.sourceHeight, 400);
      expect(processed.width, lessThan(400));
      expect(processed.height, lessThan(400));
      expect(decoded.width, processed.width);
      expect(decoded.height, processed.height);
      expect(
        processed.base64.length,
        lessThanOrEqualTo(SettingsModel.maxLogoBase64Bytes),
      );
    },
  );
}
