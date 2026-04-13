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
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType, name: fileName)],
        text: text,
      ),
    );
  } else {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        text: text,
      ),
    );
  }
}

/// Opens WhatsApp with a pre-filled message.
/// [phone] should include country code without '+', e.g. '966501234567'.
Future<bool> openWhatsApp({
  required String phone,
  required String message,
}) async {
  final normalizedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
  final encoded = Uri.encodeComponent(message);
  final primaryUri = Uri.parse(
    'whatsapp://send?phone=$normalizedPhone&text=$encoded',
  );
  final fallbackUris = [
    Uri.parse('https://wa.me/$normalizedPhone?text=$encoded'),
    Uri.parse(
      'https://api.whatsapp.com/send?phone=$normalizedPhone&text=$encoded',
    ),
    Uri.parse(
      'https://web.whatsapp.com/send?phone=$normalizedPhone&text=$encoded',
    ),
  ];

  if (await launchUrl(
    primaryUri,
    mode: LaunchMode.externalNonBrowserApplication,
  )) {
    return true;
  }

  for (final uri in fallbackUris) {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return true;
    }
  }

  return false;
}

/// Share plain text via the OS share sheet.
Future<void> shareText(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}
