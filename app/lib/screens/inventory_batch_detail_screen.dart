import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/inventory_provider.dart';
import '../models/inventory_batch_model.dart';
import '../models/inventory_item_model.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_message.dart';

class InventoryBatchDetailScreen extends ConsumerWidget {
  final String batchId;
  const InventoryBatchDetailScreen({super.key, required this.batchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(inventoryBatchDetailProvider(batchId));
    final items = ref.watch(inventoryItemsByBatchProvider(batchId));

    return Scaffold(
      appBar: AppBar(title: Text(tr('batch_detail', ref))),
      body: batch.when(
        data: (b) {
          if (b == null) return Center(child: Text(tr('batch_not_found', ref)));
          return Column(
            children: [
              _BatchHeader(batch: b, batchId: batchId),
              const Divider(height: 1),
              Expanded(
                child: items.when(
                  data: (list) => list.isEmpty
                      ? Center(child: Text(tr('no_items_yet', ref)))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => _ItemTile(item: list[i]),
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
        error: (e, _) => Center(child: Text('${tr('error', ref)}: $e')),
      ),
    );
  }
}

class _BatchHeader extends ConsumerWidget {
  final InventoryBatchModel batch;
  final String batchId;
  const _BatchHeader({required this.batch, required this.batchId});

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
                child: Text(batch.productId,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              StatusChip(status: batch.status),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              _Stat(
                  label: tr('produced', ref),
                  value: batch.qtyProduced.toString()),
              _Stat(
                  label: tr('passed', ref), value: batch.qtyPassed.toString()),
              _Stat(
                  label: tr('rejected', ref),
                  value: batch.qtyRejected.toString()),
              _Stat(
                  label: tr('cost_per_pair', ref),
                  value: AppFormatters.sar(batch.costPerPair)),
              _Stat(
                  label: tr('total_cost', ref),
                  value: AppFormatters.sar(batch.costTotal)),
            ],
          ),
          const SizedBox(height: 12),
          RoleGuard(
            allowed: (u) => u.isManager,
            child: _StatusButtons(batch: batch, batchId: batchId),
          ),
        ],
      ),
    );
  }
}

class _StatusButtons extends ConsumerWidget {
  final InventoryBatchModel batch;
  final String batchId;
  const _StatusButtons({required this.batch, required this.batchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(inventoryBatchNotifierProvider.notifier);
    return Row(
      children: [
        if (batch.status == 'draft')
          FilledButton(
            onPressed: () async {
              try {
                await notifier.updateStatus(batchId, 'in_production');
                if (context.mounted) {
                  AppMessage.success(context, ref, 'success_status_updated');
                }
              } catch (e) {
                if (context.mounted) AppMessage.error(context, ref, e);
              }
            },
            child: Text(tr('start_production', ref)),
          ),
        if (batch.status == 'in_production')
          FilledButton(
            onPressed: () async {
              try {
                await notifier.updateStatus(batchId, 'qc_pending');
                if (context.mounted) {
                  AppMessage.success(context, ref, 'success_status_updated');
                }
              } catch (e) {
                if (context.mounted) AppMessage.error(context, ref, e);
              }
            },
            child: Text(tr('move_to_qc', ref)),
          ),
        if (batch.status == 'qc_passed')
          FilledButton(
            onPressed: () async {
              try {
                await notifier.updateStatus(batchId, 'complete');
                if (context.mounted) {
                  AppMessage.success(context, ref, 'success_status_updated');
                }
              } catch (e) {
                if (context.mounted) AppMessage.error(context, ref, e);
              }
            },
            child: Text(tr('mark_complete', ref)),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final InventoryItemModel item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${item.productName} — Size ${item.size}'),
      subtitle: Text('Cost: ${AppFormatters.sar(item.costPerPair)}'),
      trailing: StatusChip(status: item.status),
    );
  }
}
