import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/supplier_provider.dart';
import '../models/purchase_order_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class PurchaseOrdersListScreen extends ConsumerStatefulWidget {
  const PurchaseOrdersListScreen({super.key});

  @override
  ConsumerState<PurchaseOrdersListScreen> createState() =>
      _PurchaseOrdersListScreenState();
}

class _PurchaseOrdersListScreenState
    extends ConsumerState<PurchaseOrdersListScreen> {
  String? _statusFilter;

  static const _statuses = [
    'draft',
    'sent',
    'partially_received',
    'received',
    'closed',
    'cancelled',
  ];

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(purchaseOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('purchase_orders', ref)),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _statusFilter = v),
            itemBuilder: (_) => [
              PopupMenuItem(value: null, child: Text(tr('all', ref))),
              ..._statuses.map(
                (s) => PopupMenuItem(
                  value: s,
                  child: Text(s.replaceAll('_', ' ').toUpperCase()),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = orders.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Purchase Orders',
                fileName: 'purchase_orders',
                headers: [
                  tr('purchase_order', ref),
                  tr('supplier', ref),
                  tr('status', ref),
                  tr('total', ref),
                  tr('expected_delivery_label', ref),
                  tr('created_at', ref)
                ],
                rows: data
                    .map((o) => [
                          o.id,
                          o.supplierName,
                          o.status,
                          o.total,
                          AppFormatters.date(o.expectedDelivery),
                          AppFormatters.date(o.createdAt)
                        ])
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: orders.when(
        data: (list) {
          final filtered = _statusFilter == null
              ? list
              : list.where((o) => o.status == _statusFilter).toList();
          if (filtered.isEmpty) {
            return EmptyState(message: tr('no_purchase_orders_found', ref));
          }
          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => _PurchaseOrderTile(order: filtered[i]),
          );
        },
        loading: () => const ShimmerLoading(),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isManager,
        child: FloatingActionButton(
          onPressed: () => context.push('/purchase-orders/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _PurchaseOrderTile extends StatelessWidget {
  final PurchaseOrderModel order;
  const _PurchaseOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.shopping_cart)),
      title: Text(order.supplierName),
      subtitle: Text(
        '${order.items.length} item(s) · ${AppFormatters.date(order.createdAt)}',
      ),
      trailing: StatusChip(status: order.status),
      onTap: () => context.push('/purchase-orders/${order.id}'),
    );
  }
}
