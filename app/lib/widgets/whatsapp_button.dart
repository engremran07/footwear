import 'package:flutter/material.dart';
import '../core/utils/share_helper.dart';

/// A compact icon button that opens WhatsApp for the given [phone] number.
///
/// The phone string is normalised via [normalizeWhatsAppPhone] before launching,
/// so local formats (Pakistan 03xx, Saudi 05xx) are handled automatically.
/// The button is hidden when [phone] is null or blank.
class WhatsAppIconButton extends StatelessWidget {
  final String? phone;
  final String? message;
  final double iconSize;

  const WhatsAppIconButton({
    super.key,
    required this.phone,
    this.message = '',
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final raw = phone;
    if (raw == null || raw.trim().isEmpty) return const SizedBox.shrink();

    final normalized = normalizeWhatsAppPhone(raw);
    if (!isValidWhatsAppPhone(normalized)) return const SizedBox.shrink();

    return IconButton(
      tooltip: 'WhatsApp',
      iconSize: iconSize,
      icon: const _WhatsAppIcon(),
      onPressed: () => openWhatsApp(phone: normalized, message: message ?? ''),
    );
  }
}

/// Simple hand-drawn WhatsApp logo using CustomPaint to avoid adding an
/// image asset dependency.
class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.chat, color: Color(0xFF25D366));
  }
}
