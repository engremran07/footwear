import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/order_provider.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_message.dart';

class OrderDetailScreen extends ConsumerWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderDetailProvider(orderId));
    final items = ref.watch(orderItemsProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: Text(tr('order_detail', ref))),
      body: order.when(
        data: (o) {
          if (o == null) return Center(child: Text(tr('order_not_found', ref)));
          return Column(
            children: [
              _OrderHeader(order: o, orderId: orderId),
              const Divider(height: 1),
              Expanded(
                child: items.when(
                  data: (list) => list.isEmpty
                      ? Center(child: Text(tr('no_items', ref)))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => _OrderItemTile(item: list[i]),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text('${tr('error', ref)}: $e')),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _OrderHeader extends ConsumerWidget {
  final OrderModel order;
  final String orderId;
  const _OrderHeader({required this.order, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.customerName,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              StatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(AppFormatters.dateTime(order.createdAt),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(
            '${tr('total', ref)}: ${AppFormatters.sar(order.total)}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (order.notes != null) ...[
            const SizedBox(height: 4),
            Text('${tr('notes', ref)}: ${order.notes}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          RoleGuard(
            allowed: (u) => u.isManager,
            child: _ActionButtons(order: order, orderId: orderId),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  final OrderModel order;
  final String orderId;
  const _ActionButtons({required this.order, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(orderNotifierProvider.notifier);
    return Wrap(
      spacing: 8,
      children: [
        if (order.status == 'pending' || order.status == 'processing')
          OutlinedButton(
            onPressed: () async {
              try {
                await notifier.updateStatus(orderId, 'shipped');
                if (context.mounted) {
                  AppMessage.success(context, ref, 'success_order_shipped');
                }
              } catch (e) {
                if (context.mounted) AppMessage.error(context, ref, e);
              }
            },
            child: Text(tr('mark_shipped', ref)),
          ),
        if (order.status == 'shipped')
          FilledButton(
            onPressed: () async {
              try {
                await notifier.updateStatus(orderId, 'delivered');
                if (context.mounted) {
                  AppMessage.success(context, ref, 'success_order_delivered');
                }
              } catch (e) {
                if (context.mounted) AppMessage.error(context, ref, e);
              }
            },
            child: Text(tr('mark_delivered', ref)),
          ),
        if (order.status != 'cancelled' && order.status != 'delivered')
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('cancel_order', ref)),
                  content: Text(tr('action_cannot_undo', ref)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('no', ref))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr('yes_cancel', ref))),
                  ],
                ),
              );
              if (confirmed == true) {
                try {
                  await notifier.cancel(orderId);
                  if (context.mounted) {
                    AppMessage.success(context, ref, 'success_order_cancelled');
                  }
                } catch (e) {
                  if (context.mounted) AppMessage.error(context, ref, e);
                }
              }
            },
            child: Text(tr('cancel', ref)),
          ),
      ],
    );
  }
}

class _OrderItemTile extends StatelessWidget {
  final OrderItemModel item;
  const _OrderItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${item.productName} — Size ${item.size}'),
      subtitle: Text('${item.qty} × ${AppFormatters.sar(item.unitPrice)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(AppFormatters.sar(item.subtotal),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          StatusChip(status: item.status),
        ],
      ),
    );
  }
}
