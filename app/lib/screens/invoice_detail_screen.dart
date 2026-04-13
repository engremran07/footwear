import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/snack_helper.dart';
import '../models/invoice_model.dart';
import '../providers/auth_provider.dart';
import '../providers/invoice_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/error_state.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  final String? backTo;

  const InvoiceDetailScreen({super.key, required this.invoiceId, this.backTo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));
    final isAdmin = ref.watch(authUserProvider).value?.isAdmin ?? false;

    return Scaffold(
      body: invoiceAsync.when(
        data: (inv) {
          if (inv == null) {
            return Center(child: Text(tr('not_found', ref)));
          }
          return Column(
            children: [
              if (isAdmin && inv.status != 'void')
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4, top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PopupMenuButton<String>(
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
                      ),
                    ],
                  ),
                ),
              Expanded(child: _InvoiceBody(invoice: inv)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => mappedErrorState(
          error: e,
          ref: ref,
          onRetry: () => ref.invalidate(invoiceByIdProvider(invoiceId)),
        ),
      ),
      floatingActionButton: invoiceAsync.whenOrNull(
        data: (inv) {
          if (inv == null) return null;
          return FloatingActionButton(
            onPressed: () => _exportPdf(context, ref, inv),
            tooltip: tr('share_pdf', ref),
            child: const Icon(Icons.picture_as_pdf),
          );
        },
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    InvoiceModel inv,
  ) async {
    if (action == 'void') {
      VoidRefundMode refundMode = VoidRefundMode.creditBalance;
      if (inv.amountReceived > 0 && inv.isSale) {
        final selectedMode = await showDialog<VoidRefundMode>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('void', ref)),
            content: Text(
              '${tr('confirm_void_invoice', ref)}\n\n'
              '${tr('amount_received', ref)}: ${AppFormatters.sar(inv.amountReceived)}\n'
              '${tr('outstanding_amount', ref)}: ${AppFormatters.sar(inv.outstandingAmount)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(tr('cancel', ref)),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(VoidRefundMode.cashRefund),
                child: Text(tr('void_refund_cash', ref)),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(VoidRefundMode.creditBalance),
                child: Text(tr('void_refund_credit', ref)),
              ),
            ],
          ),
        );
        if (selectedMode == null) return;
        refundMode = selectedMode;
      } else {
        final confirmed = await ConfirmDialog.show(
          context,
          title: tr('void', ref),
          message: tr('confirm_void_invoice', ref),
        );
        if (confirmed != true) return;
      }
      try {
        await ref
            .read(invoiceNotifierProvider.notifier)
            .voidInvoice(
              invoiceId: inv.id,
              total: inv.total,
              type: inv.type,
              createdBy: ref.read(authStateProvider).value?.uid ?? '',
              refundMode: refundMode,
            );
      } catch (e) {
        if (context.mounted) {
          final key = AppErrorMapper.key(e);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(tr(key, ref)));
        }
      }
    } else if (action == 'paid') {
      try {
        await ref
            .read(invoiceNotifierProvider.notifier)
            .markAsPaid(
              invoiceId: inv.id,
              routeId: inv.routeId,
              createdBy: ref.read(authStateProvider).value?.uid ?? '',
            );
      } catch (e) {
        if (context.mounted) {
          final key = AppErrorMapper.key(e);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(tr(key, ref)));
        }
      }
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    WidgetRef ref,
    InvoiceModel inv,
  ) async {
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
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
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
    final dateStr = AppFormatters.dateOnly(date);

    Color statusColor;
    switch (invoice.status) {
      case InvoiceModel.statusPaid:
        statusColor = AppTheme.clearBg(cs);
        break;
      case InvoiceModel.statusIssued:
        statusColor = AppTheme.warningBg(cs);
        break;
      case InvoiceModel.statusPartial:
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        invoice.status.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
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
                // Payment status progression
                const SizedBox(height: 12),
                _PaymentProgressBar(invoice: invoice),
                const Divider(height: 24),
                _InfoRow(
                  label: tr('shop', ref),
                  value: invoice.shopName.isNotEmpty
                      ? invoice.shopName
                      : invoice.shopName,
                ),
                _InfoRow(label: tr('date', ref), value: dateStr),
                if (invoice.linkedInvoiceId != null &&
                    invoice.linkedInvoiceId!.isNotEmpty)
                  _InfoRow(
                    label: tr('linked_invoice', ref),
                    value: invoice.linkedInvoiceId!,
                  ),
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
                  Text(
                    tr('items', ref),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...invoice.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${item.size} • ${item.color}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'x${item.qty}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              AppFormatters.sar(item.subtotal),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                  value: AppFormatters.sar(invoice.subtotal),
                ),
                if (invoice.discount > 0)
                  _TotalRow(
                    label: tr('discount', ref),
                    value: '-${AppFormatters.sar(invoice.discount)}',
                    color: cs.primary,
                  ),
                const Divider(),
                _TotalRow(
                  label: tr('total', ref),
                  value: AppFormatters.sar(invoice.total),
                  bold: true,
                  color: invoice.isSale ? cs.error : cs.primary,
                ),
                if (invoice.amountReceived > 0)
                  _TotalRow(
                    label: tr('amount_received', ref),
                    value: AppFormatters.sar(invoice.amountReceived),
                    color: cs.primary,
                  ),
                if (invoice.outstandingAmount > 0)
                  _TotalRow(
                    label: tr('outstanding_amount', ref),
                    value: AppFormatters.sar(invoice.outstandingAmount),
                    bold: true,
                    color: cs.error,
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
                  Text(
                    tr('notes', ref),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold
                ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                : null,
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 16 : null,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Payment Progress Bar ────────────────────────────────────────────────────

class _PaymentProgressBar extends ConsumerWidget {
  final InvoiceModel invoice;
  const _PaymentProgressBar({required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final steps = ['draft', 'issued', 'partial', 'paid'];
    final stepLabels = [
      tr('invoice_step_draft', ref),
      tr('invoice_step_issued', ref),
      tr('partial', ref),
      tr('invoice_step_paid', ref),
    ];
    final currentIdx = invoice.status == InvoiceModel.statusVoid
        ? -1
        : steps.indexOf(invoice.status);
    final isVoid = invoice.status == 'void';

    if (isVoid) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel, size: 16, color: cs.onErrorContainer),
            const SizedBox(width: 6),
            Text(
              tr('invoice_voided', ref),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: cs.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i <= currentIdx;
        final isLast = i == steps.length - 1;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? cs.primary : cs.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: isActive
                    ? Icon(Icons.check, size: 14, color: cs.onPrimary)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 4),
              Text(
                stepLabels[i],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: i < currentIdx
                        ? cs.primary
                        : cs.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
