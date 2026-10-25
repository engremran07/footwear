import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as image;

import '../../models/settings_model.dart';

class WorkspaceLogoProcessingException implements Exception {
  const WorkspaceLogoProcessingException(
    this.code, {
    this.sourceBytes,
    this.encodedLength,
    this.width,
    this.height,
  });

  final String code;
  final int? sourceBytes;
  final int? encodedLength;
  final int? width;
  final int? height;

  @override
  String toString() => code;
}

class ProcessedWorkspaceLogo {
  const ProcessedWorkspaceLogo._({
    required this.pngBytes,
    required this.base64,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.width,
    required this.height,
  });

  final Uint8List pngBytes;
  final String base64;
  final int sourceWidth;
  final int sourceHeight;
  final int width;
  final int height;
}

class WorkspaceLogoProcessor {
  WorkspaceLogoProcessor._();

  static const maxWidth = 800;
  static const maxHeight = 400;
  static const maxSourceBytes = 20 * 1024 * 1024;

  static Future<ProcessedWorkspaceLogo> process(Uint8List sourceBytes) async {
    if (sourceBytes.isEmpty) {
      throw const WorkspaceLogoProcessingException(
        'settings_logo_invalid_image',
      );
    }
    if (sourceBytes.lengthInBytes > maxSourceBytes) {
      throw WorkspaceLogoProcessingException(
        'settings_logo_source_too_large',
        sourceBytes: sourceBytes.lengthInBytes,
      );
    }

    final result = kIsWeb
        ? _processBytes(sourceBytes)
        : await Isolate.run(() => _processBytes(sourceBytes));
    final code = result['code']! as String;
    if (code != 'ok') {
      throw WorkspaceLogoProcessingException(
        code,
        sourceBytes: sourceBytes.lengthInBytes,
        encodedLength: result['encoded_length'] as int?,
        width: result['width'] as int?,
        height: result['height'] as int?,
      );
    }

    return ProcessedWorkspaceLogo._(
      pngBytes: result['png_bytes']! as Uint8List,
      base64: result['base64']! as String,
      sourceWidth: result['source_width']! as int,
      sourceHeight: result['source_height']! as int,
      width: result['width']! as int,
      height: result['height']! as int,
    );
  }

  static Map<String, Object?> _processBytes(Uint8List sourceBytes) {
    try {
      final decoded = image.decodeImage(sourceBytes);
      if (decoded == null) return const {'code': 'settings_logo_invalid_image'};

      final oriented = image.bakeOrientation(decoded);
      final scale = [
        1.0,
        maxWidth / oriented.width,
        maxHeight / oriented.height,
      ].reduce((current, next) => current < next ? current : next);
      final width = (oriented.width * scale).round().clamp(1, maxWidth).toInt();
      final height = (oriented.height * scale)
          .round()
          .clamp(1, maxHeight)
          .toInt();
      final resized = width == oriented.width && height == oriented.height
          ? oriented
          : image.copyResize(
              oriented,
              width: width,
              height: height,
              interpolation: image.Interpolation.linear,
            );
      final pngBytes = Uint8List.fromList(image.encodePng(resized, level: 9));
      final base64 = base64Encode(pngBytes);
      if (base64.length > SettingsModel.maxLogoBase64Bytes) {
        return {
          'code': 'settings_logo_encoded_too_large',
          'encoded_length': base64.length,
          'width': width,
          'height': height,
        };
      }

      return {
        'code': 'ok',
        'png_bytes': pngBytes,
        'base64': base64,
        'source_width': oriented.width,
        'source_height': oriented.height,
        'width': width,
        'height': height,
      };
    } on RangeError {
      return const {'code': 'settings_logo_invalid_image'};
    } on FormatException {
      return const {'code': 'settings_logo_invalid_image'};
    } on image.ImageException {
      return const {'code': 'settings_logo_processing_failed'};
    }
  }
}
