import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';
import '../models/shop_model.dart';
import '../providers/auth_provider.dart';
import '../providers/shop_provider.dart';
import '../widgets/empty_state.dart';

class ShopsListScreen extends ConsumerStatefulWidget {
  const ShopsListScreen({super.key});
  @override
  ConsumerState<ShopsListScreen> createState() => _ShopsListScreenState();
}

class _ShopsListScreenState extends ConsumerState<ShopsListScreen> {
  String _search = '';
  bool _outstandingOnly = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final shopsAsync = user?.isSeller == true && user?.assignedRouteId != null
        ? ref.watch(shopsByRouteProvider(user!.assignedRouteId!))
        : ref.watch(shopsProvider);
    final canCreateShop =
        user != null && (user.isAdmin || user.assignedRouteId != null);

    return Scaffold(
      appBar: AppBar(title: Text(tr('shops', ref))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: tr('search', ref),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text(tr('all', ref)),
                  selected: !_outstandingOnly,
                  onSelected: (_) => setState(() => _outstandingOnly = false),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(tr('outstanding', ref)),
                  selected: _outstandingOnly,
                  selectedColor: Colors.red.shade100,
                  avatar: _outstandingOnly
                      ? null
                      : Icon(Icons.warning_amber,
                          size: 16, color: Colors.red.shade700),
                  onSelected: (_) => setState(() => _outstandingOnly = true),
                ),
              ],
            ),
          ),
          // Stats strip — derived from the live shop list
          shopsAsync
                  .whenData((shops) => _ShopStatsStrip(shops: shops))
                  .valueOrNull ??
              const SizedBox.shrink(),
          Expanded(
            child: shopsAsync.when(
              data: (shops) {
                final filtered = shops.where((s) {
                  if (_search.isNotEmpty &&
                      !s.name.toLowerCase().contains(_search) &&
                      !(s.phone?.contains(_search) ?? false)) {
                    return false;
                  }
                  if (_outstandingOnly && s.balance <= 0) return false;
                  return true;
                }).toList();

                if (_outstandingOnly) {
                  filtered.sort((a, b) => b.balance.compareTo(a.balance));
                }

                if (filtered.isEmpty) {
                  return EmptyState(
                      icon: Icons.store, message: tr('no_shops', ref));
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _ShopTile(shop: filtered[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
      floatingActionButton: canCreateShop
          ? FloatingActionButton(
              onPressed: () => context.push('/shops/new'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// ── Stats strip ───────────────────────────────────────────────────────────────

class _ShopStatsStrip extends StatelessWidget {
  final List<ShopModel> shops;
  const _ShopStatsStrip({required this.shops});

  @override
  Widget build(BuildContext context) {
    final total = shops.length;
    final withDebt = shops.where((s) => s.balance > 0).toList();
    final totalOutstanding = withDebt.fold(0.0, (sum, s) => sum + s.balance);

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
          _Stat(
            icon: Icons.store,
            label: 'Total',
            value: '$total',
            color: Theme.of(context).colorScheme.primary,
          ),
          _Divider(),
          _Stat(
            icon: Icons.warning_amber,
            label: 'Overdue',
            value: '${withDebt.length}',
            color: Colors.orange.shade700,
          ),
          _Divider(),
          _Stat(
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

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        width: 1,
        color: Theme.of(context).dividerColor,
      );
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _Stat(
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

class _ShopTile extends ConsumerWidget {
  final ShopModel shop;
  const _ShopTile({required this.shop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDebt = shop.balance > 0;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasDebt ? Colors.red.shade50 : Colors.green.shade50,
          child: Icon(Icons.store,
              color: hasDebt ? Colors.red.shade700 : Colors.green.shade700),
        ),
        title: Text(shop.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (shop.phone != null) shop.phone,
            'R${shop.routeNumber}',
            if (shop.area != null) shop.area,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: hasDebt ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            hasDebt ? AppFormatters.sar(shop.balance) : tr('clear', ref),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: hasDebt ? Colors.red.shade700 : Colors.green.shade700,
            ),
          ),
        ),
        onTap: () => context.push('/shops/${shop.id}'),
      ),
    );
  }
}
