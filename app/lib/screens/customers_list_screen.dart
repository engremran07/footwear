import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';
import '../models/customer_model.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../widgets/empty_state.dart';

class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key});
  @override
  ConsumerState<CustomersListScreen> createState() =>
      _CustomersListScreenState();
}

class _CustomersListScreenState extends ConsumerState<CustomersListScreen> {
  String _search = '';
  bool _outstandingOnly = false;

  @override
  Widget build(BuildContext context) {
    // Always watch the full list so the stats strip reflects totals,
    // even when the filter is active.
    final allCustomersAsync = ref.watch(customersProvider);
    final asyncCustomers = _outstandingOnly
        ? ref.watch(outstandingCustomersProvider)
        : allCustomersAsync;
    final user = ref.watch(authUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('customers', ref)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: tr('search_by_name', ref),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(tr('outstanding', ref)),
                  selected: _outstandingOnly,
                  onSelected: (v) => setState(() => _outstandingOnly = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Stats strip — always uses the full (unfiltered) customer list
          allCustomersAsync
                  .whenData((all) => _CustomerStatsStrip(customers: all))
                  .valueOrNull ??
              const SizedBox.shrink(),
          Expanded(
            child: asyncCustomers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (customers) {
                final filtered = _search.isEmpty
                    ? customers
                    : customers
                        .where((c) =>
                            c.name.toLowerCase().contains(_search) ||
                            (c.phone ?? '').contains(_search))
                        .toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    message: tr('no_results_found', ref),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final balColor = c.balance > 0
                        ? Colors.red.shade700
                        : Colors.green.shade700;
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        ),
                      ),
                      title: Text(c.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [c.phone, c.city]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' · '),
                      ),
                      trailing: Text(
                        AppFormatters.sar(c.balance.abs()),
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: balColor),
                      ),
                      onTap: () => context.push('/customers/${c.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: (user != null)
          ? FloatingActionButton(
              heroTag: 'fab_customer',
              onPressed: () => context.push('/customers/new'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// ── Stats strip ───────────────────────────────────────────────────────────────

class _CustomerStatsStrip extends StatelessWidget {
  final List<CustomerModel> customers;
  const _CustomerStatsStrip({required this.customers});

  @override
  Widget build(BuildContext context) {
    final total = customers.length;
    final withDebt = customers.where((c) => c.balance > 0).toList();
    final totalOutstanding = withDebt.fold(0.0, (sum, c) => sum + c.balance);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _CStat(
            icon: Icons.people,
            label: 'Total',
            value: '$total',
            color: Theme.of(context).colorScheme.primary,
          ),
          _CDivider(),
          _CStat(
            icon: Icons.warning_amber,
            label: 'Overdue',
            value: '${withDebt.length}',
            color: Colors.orange.shade700,
          ),
          _CDivider(),
          _CStat(
            icon: Icons.account_balance_wallet,
            label: 'Outstanding',
            value: AppFormatters.compact(totalOutstanding),
            color: totalOutstanding > 0
                ? Colors.red.shade700
                : Colors.green.shade700,
          ),
        ],
      ),
    );
  }
}

class _CDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        width: 1,
        color: Theme.of(context).dividerColor,
      );
}

class _CStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _CStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13, color: color)),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.grey.shade600)),
        ],
      );
}
