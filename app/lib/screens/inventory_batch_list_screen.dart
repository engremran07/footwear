import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/inventory_provider.dart';
import '../models/inventory_batch_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class InventoryBatchListScreen extends ConsumerStatefulWidget {
  const InventoryBatchListScreen({super.key});

  @override
  ConsumerState<InventoryBatchListScreen> createState() =>
      _InventoryBatchListScreenState();
}

class _InventoryBatchListScreenState
    extends ConsumerState<InventoryBatchListScreen> {
  String? _statusFilter;

  static const _statuses = [
    'draft',
    'in_production',
    'qc_pending',
    'qc_issues',
    'qc_passed',
    'complete',
  ];

  @override
  Widget build(BuildContext context) {
    final batches = ref.watch(inventoryBatchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('inventory_batches', ref)),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _statusFilter = v),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: null,
                child: Text(tr('all_statuses', ref)),
              ),
              ..._statuses.map((s) => PopupMenuItem(
                    value: s,
                    child: Text(s.replaceAll('_', ' ').toUpperCase()),
                  )),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = batches.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Inventory Batches',
                fileName: 'inventory_batches',
                headers: [
                  'ID',
                  tr('product', ref),
                  tr('status', ref),
                  tr('source_label', ref),
                  tr('qty_produced', ref),
                  tr('passed_qty', ref),
                  tr('rejected_qty', ref),
                  tr('total_cost', ref),
                  tr('cost_per_pair', ref),
                  tr('created_at', ref)
                ],
                rows: data
                    .map((b) => [
                          b.id,
                          b.productId,
                          b.status,
                          b.source,
                          b.qtyProduced,
                          b.qtyPassed,
                          b.qtyRejected,
                          b.costTotal,
                          b.costPerPair,
                          AppFormatters.date(b.createdAt)
                        ])
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: batches.when(
        data: (list) {
          final filtered = _statusFilter == null
              ? list
              : list.where((b) => b.status == _statusFilter).toList();
          if (filtered.isEmpty) {
            return EmptyState(
              message: _statusFilter != null
                  ? '${tr('no_batches_status', ref)} $_statusFilter'
                  : tr('no_inventory_batches', ref),
              icon: Icons.layers_outlined,
            );
          }
          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => _BatchTile(batch: filtered[i]),
          );
        },
        loading: () => const ShimmerLoading(),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isManager,
        child: FloatingActionButton(
          onPressed: () => context.push('/inventory/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  final InventoryBatchModel batch;
  const _BatchTile({required this.batch});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.layers)),
      title: Text(batch.productId),
      subtitle: Text(
          'Produced: ${batch.qtyProduced} · Passed: ${batch.qtyPassed} · Rejected: ${batch.qtyRejected}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip(status: batch.status),
          const SizedBox(height: 4),
          Text(AppFormatters.date(batch.createdAt),
              style: const TextStyle(fontSize: 11)),
        ],
      ),
      onTap: () => context.push('/inventory/${batch.id}'),
    );
  }
}
