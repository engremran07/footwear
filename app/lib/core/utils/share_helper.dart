import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'file_saver.dart';

/// Normalizes a raw phone string to an international WhatsApp number
/// (digits only, no leading +).
///
/// Rules applied in order:
///  1. Strip all non-digit characters.
///  2. Strip a leading `00` (international dialling prefix).
///  3. Pakistan local: `03xxxxxxxx` → `923xxxxxxxx`
///  4. Saudi local:   `05xxxxxxxx` → `9665xxxxxxxx`
///  5. Everything else is left as-is (assumed already international).
String normalizeWhatsAppPhone(String phone) {
  // Step 1 — digits only
  var digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  // Remove leading '+' if present — we work in pure digits after this
  if (digits.startsWith('+')) digits = digits.substring(1);
  // Step 2 — strip leading international prefix 00
  if (digits.startsWith('00')) digits = digits.substring(2);
  // Step 3 — Pakistan local (03xx...)
  if (RegExp(r'^03\d{9}$').hasMatch(digits)) {
    return '92${digits.substring(1)}'; // 03x → 923x
  }
  // Step 4 — Saudi local (05xx...)
  if (RegExp(r'^05\d{8}$').hasMatch(digits)) {
    return '966${digits.substring(1)}'; // 05x → 9665x
  }
  return digits;
}

bool isValidWhatsAppPhone(String phone) {
  final normalizedPhone = normalizeWhatsAppPhone(phone);
  return RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(normalizedPhone);
}

/// Shares raw bytes via the OS share sheet (WhatsApp, email, etc.).
Future<void> shareFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? text,
}) async {
  XFile? fileToShare;
  try {
    // Try to save to temp first (mobile), fall back to in-memory (web/error).
    final path = await saveTempFile(bytes, fileName);
    if (path != null) {
      fileToShare = XFile(path, mimeType: mimeType, name: fileName);
    }
  } catch (_) {
    // Fall back to an in-memory payload when filesystem save is unavailable.
  }

  fileToShare ??= XFile.fromData(bytes, mimeType: mimeType, name: fileName);
  await SharePlus.instance.share(
    ShareParams(
      files: [fileToShare],
      text: text,
      fileNameOverrides: [fileName],
    ),
  );
}

/// Opens WhatsApp with a pre-filled message.
/// [phone] should include country code without '+', e.g. '966501234567'.
Future<bool> openWhatsApp({
  required String phone,
  required String message,
}) async {
  if (!isValidWhatsAppPhone(phone)) return false;
  final normalizedPhone = normalizeWhatsAppPhone(phone);
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
