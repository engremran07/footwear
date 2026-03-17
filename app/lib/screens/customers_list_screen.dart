import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/customer_provider.dart';
import '../models/customer_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key});

  @override
  ConsumerState<CustomersListScreen> createState() =>
      _CustomersListScreenState();
}

class _CustomersListScreenState extends ConsumerState<CustomersListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('customers', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = customers.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Customers',
                fileName: 'customers',
                headers: [
                  tr('name', ref),
                  tr('phone', ref),
                  tr('email', ref),
                  tr('city', ref),
                  tr('country', ref),
                  tr('balance', ref),
                  tr('total_orders', ref)
                ],
                rows: data
                    .map((c) => [
                          c.name,
                          c.phone,
                          c.email ?? '',
                          c.city ?? '',
                          c.country,
                          c.balance,
                          c.totalOrders
                        ])
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              hintText: tr('search_by_name', ref),
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: customers.when(
              data: (list) {
                final filtered = list
                    .where((c) =>
                        _search.isEmpty ||
                        c.name.toLowerCase().contains(_search))
                    .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    message: tr('no_customers_found', ref),
                    icon: Icons.person_outline,
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _CustomerTile(customer: filtered[i]),
                );
              },
              loading: () => const ShimmerLoading(),
              error: (e, _) => ErrorState(message: e.toString()),
            ),
          ),
        ],
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isManager,
        child: FloatingActionButton(
          onPressed: () => context.push('/customers/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  final CustomerModel customer;
  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(child: Text(customer.name[0].toUpperCase())),
      title: Text(customer.name),
      subtitle: Text(customer.phone),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${tr('orders_count', ref)}: ${customer.totalOrders}'),
          if (customer.balance > 0)
            Text(
              '${tr('bal_short', ref)}: ${AppFormatters.sar(customer.balance)}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
        ],
      ),
      onTap: () => context.push('/customers/${customer.id}'),
    );
  }
}
