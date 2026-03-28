import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';
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
    final asyncCustomers = _outstandingOnly
        ? ref.watch(outstandingCustomersProvider)
        : ref.watch(customersProvider);
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
