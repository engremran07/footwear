import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/pdf_export.dart';
import '../models/invoice_model.dart';
import '../providers/auth_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/confirm_dialog.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));
    final isAdmin = ref.watch(authUserProvider).valueOrNull?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('invoice_detail', ref)),
        actions: [
          if (isAdmin)
            invoiceAsync.whenOrNull(
                  data: (inv) {
                    if (inv == null || inv.status == 'void') return null;
                    return PopupMenuButton<String>(
                      onSelected: (action) =>
                          _handleAction(context, ref, action, inv),
                      itemBuilder: (_) => [
                        if (inv.status != InvoiceModel.statusPaid)
                          PopupMenuItem(
                            value: 'paid',
                            child: Text(tr('mark_paid', ref)),
                          ),
                        PopupMenuItem(
                          value: 'void',
                          child: Text(tr('void', ref)),
                        ),
                      ],
                    );
                  },
                ) ??
                const SizedBox.shrink(),
        ],
      ),
      body: invoiceAsync.when(
        data: (inv) {
          if (inv == null) {
            return Center(child: Text(tr('not_found', ref)));
          }
          return _InvoiceBody(invoice: inv);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: invoiceAsync.whenOrNull(
        data: (inv) {
          if (inv == null) return null;
          return FloatingActionButton(
            onPressed: () => _exportPdf(context, ref, inv),
            child: const Icon(Icons.picture_as_pdf),
          );
        },
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action,
      InvoiceModel inv) async {
    if (action == 'void') {
      final confirmed = await ConfirmDialog.show(
        context,
        title: tr('void', ref),
        message: tr('confirm_void_invoice', ref),
      );
      if (confirmed != true) return;
      try {
        await ref.read(invoiceNotifierProvider.notifier).voidInvoice(
              invoiceId: inv.id,
              customerId: inv.customerId,
              total: inv.total,
              type: inv.type,
            );
      } catch (e) {
        if (context.mounted) {
          final key = AppErrorMapper.key(e);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr(key, ref))));
        }
      }
    } else if (action == 'paid') {
      try {
        await ref
            .read(invoiceNotifierProvider.notifier)
            .markAsPaid(invoiceId: inv.id);
      } catch (e) {
        if (context.mounted) {
          final key = AppErrorMapper.key(e);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr(key, ref))));
        }
      }
    }
  }

  Future<void> _exportPdf(
      BuildContext context, WidgetRef ref, InvoiceModel inv) async {
    try {
      final locale = ref.read(appLocaleProvider);
      final settings = await ref.read(settingsProvider.future);
      final bytes = await generateInvoicePdf(
        invoice: inv,
        companyName: settings.companyName,
        currency: settings.currency,
        locale: locale,
        logoBytes: settings.logoBytes,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${inv.invoiceNumber}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _InvoiceBody extends ConsumerWidget {
  final InvoiceModel invoice;
  const _InvoiceBody({required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final date = invoice.createdAt.toDate();
    final dateStr = '${date.day}/${date.month}/${date.year}';

    Color statusColor;
    switch (invoice.status) {
      case InvoiceModel.statusPaid:
        statusColor = AppTheme.clearBg(cs);
        break;
      case InvoiceModel.statusIssued:
        statusColor = AppTheme.warningBg(cs);
        break;
      case 'void':
        statusColor = cs.errorContainer;
        break;
      default:
        statusColor = cs.surfaceContainerHighest;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        invoice.invoiceNumber,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        invoice.status.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  invoice.isSale
                      ? tr('sale_invoice', ref)
                      : tr('credit_note', ref),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const Divider(height: 24),
                _InfoRow(
                    label: tr('customer', ref), value: invoice.customerName),
                if (invoice.shopName.isNotEmpty)
                  _InfoRow(label: tr('shop', ref), value: invoice.shopName),
                _InfoRow(label: tr('date', ref), value: dateStr),
                if (invoice.linkedInvoiceId != null &&
                    invoice.linkedInvoiceId!.isNotEmpty)
                  _InfoRow(
                      label: tr('linked_invoice', ref),
                      value: invoice.linkedInvoiceId!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Items table
        if (invoice.items.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('items', ref),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...invoice.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.productName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                  Text(
                                    '${item.size} • ${item.color}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Text('x${item.qty}',
                                  textAlign: TextAlign.center),
                            ),
                            Expanded(
                              child: Text(
                                AppFormatters.sar(item.subtotal),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Totals card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _TotalRow(
                    label: tr('subtotal', ref),
                    value: AppFormatters.sar(invoice.subtotal)),
                if (invoice.discount > 0)
                  _TotalRow(
                      label: tr('discount', ref),
                      value: '-${AppFormatters.sar(invoice.discount)}',
                      color: cs.primary),
                const Divider(),
                _TotalRow(
                  label: tr('total', ref),
                  value: AppFormatters.sar(invoice.total),
                  bold: true,
                  color: invoice.isSale ? cs.error : cs.primary,
                ),
              ],
            ),
          ),
        ),
        if (invoice.notes != null && invoice.notes!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('notes', ref),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(invoice.notes!),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _TotalRow(
      {required this.label,
      required this.value,
      this.bold = false,
      this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                  : null),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontSize: bold ? 16 : null,
                color: color,
              )),
        ],
      ),
    );
  }
}
