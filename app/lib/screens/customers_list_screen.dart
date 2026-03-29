import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/customer_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/user_provider.dart';
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
    final usersAsync =
        user?.isAdmin == true ? ref.watch(allUsersProvider) : null;

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

                // Admin: grouped by seller
                if (user?.isAdmin == true) {
                  final users = usersAsync?.valueOrNull ?? [];
                  return _AdminGroupedCustomersView(
                      customers: filtered, users: users);
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final cs = Theme.of(context).colorScheme;
                    final balColor = c.balance > 0
                        ? AppTheme.debtFg(cs)
                        : AppTheme.clearFg(cs);
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
            color: AppTheme.warningFg(Theme.of(context).colorScheme),
          ),
          _CDivider(),
          _CStat(
            icon: Icons.account_balance_wallet,
            label: 'Outstanding',
            value: AppFormatters.compact(totalOutstanding),
            color: totalOutstanding > 0
                ? AppTheme.debtFg(Theme.of(context).colorScheme)
                : AppTheme.clearFg(Theme.of(context).colorScheme),
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}

// ── Admin grouped view ────────────────────────────────────────────────────────

class _AdminGroupedCustomersView extends StatefulWidget {
  final List<CustomerModel> customers;
  final List<UserModel> users;
  const _AdminGroupedCustomersView(
      {required this.customers, required this.users});

  @override
  State<_AdminGroupedCustomersView> createState() =>
      _AdminGroupedCustomersViewState();
}

class _AdminGroupedCustomersViewState
    extends State<_AdminGroupedCustomersView> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final nameMap = {for (final u in widget.users) u.id: u.displayName};

    final Map<String, List<CustomerModel>> grouped = {};
    for (final c in widget.customers) {
      grouped.putIfAbsent(c.createdBy, () => []).add(c);
    }

    final sections = grouped.entries.toList()
      ..sort((a, b) {
        final na = nameMap[a.key] ?? a.key;
        final nb = nameMap[b.key] ?? b.key;
        return na.compareTo(nb);
      });

    if (sections.isEmpty) {
      return const EmptyState(
          icon: Icons.people_outline, message: 'No customers found');
    }

    // Flat item list respecting collapsed state
    final flatItems = <({bool isHeader, String sectionKey, int itemIdx})>[];
    for (final s in sections) {
      flatItems.add((isHeader: true, sectionKey: s.key, itemIdx: -1));
      if (!_collapsed.contains(s.key)) {
        for (int i = 0; i < s.value.length; i++) {
          flatItems.add((isHeader: false, sectionKey: s.key, itemIdx: i));
        }
      }
    }

    final sectionMap = {for (final s in sections) s.key: s};

    return ListView.builder(
      itemCount: flatItems.length,
      itemBuilder: (context, index) {
        final entry = flatItems[index];
        final section = sectionMap[entry.sectionKey]!;
        if (entry.isHeader) {
          final cs = Theme.of(context).colorScheme;
          final sellerName = nameMap[section.key] ?? section.key;
          final isCollapsed = _collapsed.contains(entry.sectionKey);
          return InkWell(
            onTap: () => setState(() {
              if (isCollapsed) {
                _collapsed.remove(entry.sectionKey);
              } else {
                _collapsed.add(entry.sectionKey);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: cs.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(Icons.person, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sellerName,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: cs.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '${section.value.length}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        size: 18, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }
        final c = section.value[entry.itemIdx];
        final cs = Theme.of(context).colorScheme;
        final balColor =
            c.balance > 0 ? AppTheme.debtFg(cs) : AppTheme.clearFg(cs);
        return ListTile(
          leading: CircleAvatar(
            child: Text(
              c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
            ),
          ),
          title:
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [c.phone, c.city]
                .where((e) => e != null && e.isNotEmpty)
                .join(' · '),
          ),
          trailing: Text(
            AppFormatters.sar(c.balance.abs()),
            style: TextStyle(fontWeight: FontWeight.bold, color: balColor),
          ),
          onTap: () => context.push('/customers/${c.id}'),
        );
      },
    );
  }
}
