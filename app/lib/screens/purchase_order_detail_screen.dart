import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/supplier_provider.dart';
import '../widgets/error_state.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../widgets/confirm_dialog.dart';
import '../models/purchase_order_model.dart';
import '../core/utils/formatters.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_message.dart';

class PurchaseOrderDetailScreen extends ConsumerWidget {
  final String id;
  const PurchaseOrderDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(purchaseOrderDetailProvider(id));

    return orderAsync.when(
      data: (order) {
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('purchase_order', ref))),
            body: ErrorState(message: tr('order_not_found', ref)),
          );
        }
        return _PurchaseOrderDetailView(order: order);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(tr('purchase_order', ref))),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(tr('purchase_order', ref))),
        body: ErrorState(message: e.toString()),
      ),
    );
  }
}

class _PurchaseOrderDetailView extends ConsumerWidget {
  final PurchaseOrderModel order;
  const _PurchaseOrderDetailView({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${tr('po_prefix', ref)} – ${order.supplierName}'),
        actions: [StatusChip(status: order.status)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(order: order),
          const SizedBox(height: 12),
          Text(tr('line_items', ref),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...order.items.map((item) => _ItemTile(item: item)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${tr('total', ref)}: ${AppFormatters.sar(order.total)}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 24),
          _ActionButtons(order: order),
        ],
      ),
    );
  }
}

class _InfoCard extends ConsumerWidget {
  final PurchaseOrderModel order;
  const _InfoCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(tr('supplier', ref), order.supplierName),
            _Row(tr('created_date', ref), AppFormatters.date(order.createdAt)),
            if (order.expectedDelivery != null)
              _Row(tr('expected_delivery', ref),
                  AppFormatters.date(order.expectedDelivery!)),
            if (order.receivedAt != null)
              _Row(tr('received_date', ref),
                  AppFormatters.date(order.receivedAt!)),
            if (order.inventoryBatchId != null)
              _Row(tr('inventory_batch_label', ref), order.inventoryBatchId!),
            if (order.notes != null && order.notes!.isNotEmpty)
              _Row(tr('notes', ref), order.notes!),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final qty = item['qty'] as int? ?? 0;
    final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? 0.0;
    return ListTile(
      dense: true,
      title: Text('${item['product_name']} – Size ${item['size']}'),
      subtitle: Text('Qty: $qty @ ${AppFormatters.sar(unitCost)}'),
      trailing: Text(AppFormatters.sar(qty * unitCost)),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  final PurchaseOrderModel order;
  const _ActionButtons({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RoleGuard(
      allowed: (u) => u.isManager,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (order.status == 'draft')
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: Text(tr('mark_sent', ref)),
              onPressed: () => _updateStatus(context, ref, 'sent'),
            ),
          if (order.status == 'sent' || order.status == 'partially_received')
            FilledButton.icon(
              icon: const Icon(Icons.inventory),
              label: Text(tr('mark_received', ref)),
              onPressed: () => _confirmReceive(context, ref),
            ),
          if (order.status != 'cancelled' &&
              order.status != 'closed' &&
              order.status != 'received')
            const SizedBox(height: 8),
          if (order.status != 'cancelled' &&
              order.status != 'closed' &&
              order.status != 'received')
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => _updateStatus(context, ref, 'cancelled'),
              child: Text(tr('cancel_po', ref)),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmReceive(BuildContext context, WidgetRef ref) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('mark_received', ref),
      message: tr('mark_received_info', ref),
      confirmLabel: tr('mark_received', ref),
    );
    if (confirmed && context.mounted) {
      await _updateStatus(context, ref, 'received');
    }
  }

  Future<void> _updateStatus(
      BuildContext context, WidgetRef ref, String status) async {
    try {
      await ref
          .read(purchaseOrderNotifierProvider.notifier)
          .updateStatus(order.id, status);
      if (context.mounted) {
        AppMessage.success(context, ref, 'success_status_updated');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }
}
