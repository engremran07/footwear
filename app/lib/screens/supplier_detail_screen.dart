import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/supplier_provider.dart';
import '../widgets/error_state.dart';
import '../widgets/role_guard.dart';
import '../models/supplier_model.dart';
import '../core/utils/formatters.dart';
import '../core/l10n/app_locale.dart';

class SupplierDetailScreen extends ConsumerWidget {
  final String id;
  const SupplierDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplierAsync = ref.watch(supplierDetailProvider(id));

    return supplierAsync.when(
      data: (supplier) {
        if (supplier == null) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('supplier', ref))),
            body: ErrorState(message: tr('supplier_not_found', ref)),
          );
        }
        return _SupplierDetailView(supplier: supplier);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(tr('supplier', ref))),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(tr('supplier', ref))),
        body: ErrorState(message: e.toString()),
      ),
    );
  }
}

class _SupplierDetailView extends ConsumerWidget {
  final SupplierModel supplier;
  const _SupplierDetailView({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(purchaseOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(supplier.name),
        actions: [
          RoleGuard(
            allowed: (u) => u.isManager,
            child: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => context.push('/suppliers/${supplier.id}/edit'),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          _StatsRow(supplier: supplier),
          const Divider(),
          _InfoSection(supplier: supplier),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(tr('purchase_orders', ref),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          orders.when(
            data: (list) {
              final supplierOrders =
                  list.where((o) => o.supplierId == supplier.id).toList();
              if (supplierOrders.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('no_orders_yet', ref)),
                );
              }
              return Column(
                children: supplierOrders
                    .map(
                      (o) => ListTile(
                        title: Text('${o.items.length} item(s)'),
                        subtitle: Text(AppFormatters.date(o.createdAt)),
                        trailing: Text(AppFormatters.sar(o.total)),
                        onTap: () => context.push('/purchase-orders/${o.id}'),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${tr('error', ref)}: $e'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  final SupplierModel supplier;
  const _StatsRow({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              label: tr('total_purchased', ref),
              value: AppFormatters.sar(supplier.totalPurchased),
            ),
          ),
          Expanded(
            child: _StatItem(
              label: tr('last_order', ref),
              value: supplier.lastOrderAt != null
                  ? AppFormatters.date(supplier.lastOrderAt!)
                  : '—',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _InfoSection extends ConsumerWidget {
  final SupplierModel supplier;
  const _InfoSection({required this.supplier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _Row(tr('contact', ref), supplier.contactName),
          _Row(tr('phone', ref), supplier.phone),
          if (supplier.email != null) _Row(tr('email', ref), supplier.email!),
          if (supplier.address != null)
            _Row(tr('address', ref), supplier.address!),
          _Row(tr('payment_terms', ref), supplier.paymentTerms),
          _Row(tr('status', ref),
              supplier.active ? tr('active', ref) : tr('inactive', ref)),
        ],
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
            width: 130,
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
