import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
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
    final routesAsync =
        user?.isAdmin == true ? ref.watch(routesProvider) : null;
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
                  selectedColor: AppTheme.debtBg(Theme.of(context).colorScheme),
                  avatar: _outstandingOnly
                      ? null
                      : Icon(Icons.warning_amber,
                          size: 16,
                          color:
                              AppTheme.debtFg(Theme.of(context).colorScheme)),
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

                // Admin: grouped by route
                if (user?.isAdmin == true) {
                  final routes = routesAsync?.valueOrNull ?? [];
                  if (routes.isNotEmpty) {
                    return _AdminGroupedShopsView(
                        shops: filtered, routes: routes);
                  }
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
            color: AppTheme.warningFg(Theme.of(context).colorScheme),
          ),
          _Divider(),
          _Stat(
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}

class _ShopTile extends ConsumerWidget {
  final ShopModel shop;
  const _ShopTile({required this.shop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDebt = shop.balance > 0;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasDebt ? AppTheme.debtBg(cs) : AppTheme.clearBg(cs),
          child: Icon(Icons.store,
              color: hasDebt ? AppTheme.debtFg(cs) : AppTheme.clearFg(cs)),
        ),
        title: Text(shop.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: hasDebt ? AppTheme.debtBg(cs) : AppTheme.clearBg(cs),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              hasDebt ? AppFormatters.sar(shop.balance) : tr('clear', ref),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: hasDebt ? AppTheme.debtFg(cs) : AppTheme.clearFg(cs),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        onTap: () => context.push('/shops/${shop.id}'),
      ),
    );
  }
}

// ── Admin grouped view ────────────────────────────────────────────────────────

class _AdminGroupedShopsView extends StatefulWidget {
  final List<ShopModel> shops;
  final List<RouteModel> routes;
  const _AdminGroupedShopsView({required this.shops, required this.routes});

  @override
  State<_AdminGroupedShopsView> createState() => _AdminGroupedShopsViewState();
}

class _AdminGroupedShopsViewState extends State<_AdminGroupedShopsView> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    // Build map routeId -> RouteModel, sorted by routeNumber
    final routeMap = {for (final r in widget.routes) r.id: r};
    final sorted = List.of(widget.routes)
      ..sort((a, b) => a.routeNumber.compareTo(b.routeNumber));

    // Group shops by routeId
    final Map<String, List<ShopModel>> grouped = {};
    for (final shop in widget.shops) {
      grouped.putIfAbsent(shop.routeId, () => []).add(shop);
    }

    // Build section list sorted by routeNumber + unassigned at end
    final sections =
        <({RouteModel? route, String key, List<ShopModel> items})>[];
    for (final r in sorted) {
      final items = grouped[r.id];
      if (items != null && items.isNotEmpty) {
        sections.add((route: r, key: r.id, items: items));
      }
    }
    final knownIds = routeMap.keys.toSet();
    final unassigned =
        widget.shops.where((s) => !knownIds.contains(s.routeId)).toList();
    if (unassigned.isNotEmpty) {
      sections.add((route: null, key: '__unassigned', items: unassigned));
    }

    if (sections.isEmpty) {
      return const EmptyState(icon: Icons.store, message: 'No shops found');
    }

    // Flat list of items: each entry is either a header key or a shop index
    final flatItems = <({bool isHeader, String sectionKey, int itemIdx})>[];
    for (final s in sections) {
      flatItems.add((isHeader: true, sectionKey: s.key, itemIdx: -1));
      if (!_collapsed.contains(s.key)) {
        for (int i = 0; i < s.items.length; i++) {
          flatItems.add((isHeader: false, sectionKey: s.key, itemIdx: i));
        }
      }
    }

    // Quick lookup: sectionKey -> section
    final sectionMap = {for (final s in sections) s.key: s};

    return ListView.builder(
      itemCount: flatItems.length,
      itemBuilder: (context, index) {
        final entry = flatItems[index];
        final section = sectionMap[entry.sectionKey]!;
        if (entry.isHeader) {
          final r = section.route;
          final cs = Theme.of(context).colorScheme;
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
                  Icon(Icons.route, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r != null
                          ? 'R${r.routeNumber} · ${r.name}'
                          : 'Unassigned',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: cs.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (r?.assignedSellerName != null)
                    Text(
                      r!.assignedSellerName!,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  const SizedBox(width: 8),
                  // Per-route outstanding balance
                  Builder(builder: (_) {
                    final routeOutstanding = section.items
                        .where((s) => s.balance > 0)
                        .fold(0.0, (sum, s) => sum + s.balance);
                    if (routeOutstanding > 0) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.debtBg(cs),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            AppFormatters.compact(routeOutstanding),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.debtFg(cs),
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
                  Text(
                    '${section.items.length}',
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
        return _ShopTile(shop: section.items[entry.itemIdx]);
      },
    );
  }
}
