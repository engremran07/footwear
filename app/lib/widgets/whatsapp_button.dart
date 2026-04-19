import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';
import '../core/utils/share_helper.dart';
import '../models/shop_model.dart';
import '../providers/route_provider.dart';

/// A compact icon button that opens WhatsApp directly for [phone].
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

/// A shop-aware WhatsApp CTA button. Tapping shows a bottom sheet with
/// options: open chat, send payment reminder, or view account statement.
class WhatsAppShopCtaButton extends ConsumerWidget {
  final ShopModel shop;
  final double iconSize;

  /// Called when the user picks "View Account Statement". Typically navigates
  /// to the shop detail screen. If null the option is omitted.
  final VoidCallback? onViewStatement;

  const WhatsAppShopCtaButton({
    super.key,
    required this.shop,
    this.iconSize = 22,
    this.onViewStatement,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = shop.phone;
    if (raw == null || raw.trim().isEmpty) return const SizedBox.shrink();
    final normalized = normalizeWhatsAppPhone(raw);
    if (!isValidWhatsAppPhone(normalized)) return const SizedBox.shrink();

    return IconButton(
      tooltip: 'WhatsApp',
      iconSize: iconSize,
      icon: const _WhatsAppIcon(),
      onPressed: () => _showCtaSheet(context, ref, normalized),
    );
  }

  void _showCtaSheet(BuildContext context, WidgetRef ref, String normalized) {
    final currency = ref.read(routeCurrencyProvider(shop.routeId));
    final balance = shop.balance > 0 ? shop.balance : 0.0;
    final amountStr = AppFormatters.currency(balance, currency);
    final greeting = tr('whatsapp_greeting', ref);
    final reminderMsg = tr(
      'payment_reminder_msg',
      ref,
    ).replaceAll('%name%', shop.name).replaceAll('%amount%', amountStr);

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const _WhatsAppIcon(),
                  const SizedBox(width: 10),
                  Text(
                    shop.name,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(tr('whatsapp_open_chat', ref)),
              onTap: () {
                Navigator.pop(ctx);
                openWhatsApp(phone: normalized, message: '$greeting!');
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(tr('send_payment_reminder', ref)),
              onTap: () {
                Navigator.pop(ctx);
                openWhatsApp(phone: normalized, message: reminderMsg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(tr('whatsapp_view_statement', ref)),
              onTap: () {
                Navigator.pop(ctx);
                onViewStatement?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-branded icon using the official Font Awesome WhatsApp brand glyph.
class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();

  @override
  Widget build(BuildContext context) {
    return const FaIcon(
      FontAwesomeIcons.whatsapp,
      color: Color(0xFF25D366),
      size: 22,
    );
  }
}
