import 'dart:typed_data';
import 'share_helper.dart';

/// Mobile/desktop: save file to temp directory and open share sheet.
Future<void> downloadBytes(List<int> bytes, String fileName) async {
  await shareFile(
    bytes: Uint8List.fromList(bytes),
    fileName: fileName,
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}
