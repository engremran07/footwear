import 'dart:typed_data';

export 'file_saver_mobile.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';

/// Saves bytes to a temp file and returns the path.
/// Returns null on web (files stay in memory).
Future<String?> saveTempFile(Uint8List bytes, String fileName) async {
  // This is the stub — replaced by conditional exports above.
  return null;
}
