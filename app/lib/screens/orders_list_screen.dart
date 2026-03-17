import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/order_provider.dart';
import '../models/order_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class OrdersListScreen extends ConsumerStatefulWidget {
  const OrdersListScreen({super.key});

  @override
  ConsumerState<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends ConsumerState<OrdersListScreen> {
  String? _statusFilter;

  static const _statuses = [
    'pending',
    'processing',
    'shipped',
    'delivered',
    'cancelled'
  ];

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('orders', ref)),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _statusFilter = v),
            itemBuilder: (_) => [
              PopupMenuItem(value: null, child: Text(tr('all', ref))),
              ..._statuses.map((s) => PopupMenuItem(
                    value: s,
                    child: Text(s.toUpperCase()),
                  )),
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
                title: 'Orders',
                fileName: 'orders',
                headers: [
                  tr('order', ref),
                  tr('customer', ref),
                  tr('status', ref),
                  tr('total', ref),
                  tr('notes', ref),
                  tr('created_at', ref)
                ],
                rows: data
                    .map((o) => [
                          o.id,
                          o.customerName,
                          o.status,
                          o.total,
                          o.notes ?? '',
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
            return EmptyState(
              message: tr('no_orders_found', ref),
              icon: Icons.shopping_cart_outlined,
            );
          }
          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => _OrderTile(order: filtered[i]),
          );
        },
        loading: () => const ShimmerLoading(),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isManager,
        child: FloatingActionButton(
          onPressed: () => context.push('/orders/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final OrderModel order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.shopping_cart)),
      title: Text(order.customerName),
      subtitle: Text(AppFormatters.date(order.createdAt)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip(status: order.status),
          const SizedBox(height: 4),
          Text(AppFormatters.sar(order.total),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      onTap: () => context.push('/orders/${order.id}'),
    );
  }
}
