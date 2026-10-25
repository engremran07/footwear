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

  test('rejects lossless output above the Base64 storage cap', () async {
    final random = Random(17);
    final source = image.Image(width: 800, height: 400, numChannels: 4);
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

    await expectLater(
      WorkspaceLogoProcessor.process(
        Uint8List.fromList(image.encodePng(source)),
      ),
      throwsA(
        isA<WorkspaceLogoProcessingException>()
            .having(
              (error) => error.code,
              'code',
              'settings_logo_encoded_too_large',
            )
            .having((error) => error.width, 'width', 800)
            .having((error) => error.height, 'height', 400),
      ),
    );
  });
}
