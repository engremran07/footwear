import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'file_saver.dart';

/// Shares raw bytes via the OS share sheet (WhatsApp, email, etc.).
Future<void> shareFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? text,
}) async {
  // Try to save to temp first (mobile), fall back to in-memory (web)
  final path = await saveTempFile(bytes, fileName);
  if (path != null) {
    await Share.shareXFiles(
      [XFile(path, mimeType: mimeType, name: fileName)],
      text: text,
    );
  } else {
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      text: text,
    );
  }
}

/// Opens WhatsApp with a pre-filled message.
/// [phone] should include country code without '+', e.g. '966501234567'.
Future<bool> openWhatsApp({
  required String phone,
  required String message,
}) async {
  final encoded = Uri.encodeComponent(message);
  final uri = Uri.parse('https://wa.me/$phone?text=$encoded');
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}

/// Share plain text via the OS share sheet.
Future<void> shareText(String text) async {
  await Share.share(text);
}
