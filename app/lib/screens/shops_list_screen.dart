import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/snack_helper.dart';
import '../models/route_model.dart';
import '../models/shop_model.dart';
import '../models/transaction_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/export_sheet.dart';
import '../widgets/shimmer_loading.dart';

class ShopsListScreen extends ConsumerStatefulWidget {
  const ShopsListScreen({super.key});
  @override
  ConsumerState<ShopsListScreen> createState() => _ShopsListScreenState();
}

class _ShopsListScreenState extends ConsumerState<ShopsListScreen> {
  String _search = '';
  _ShopQuickFilter _filter = _ShopQuickFilter.collective;
  String? _selectedRouteId;

  static final Map<String, String> _searchCharMap = {
    // Arabic/Urdu letter normalization
    'أ': 'ا',
    'إ': 'ا',
    'آ': 'ا',
    'ٱ': 'ا',
    'ى': 'ي',
    'ی': 'ي',
    'ئ': 'ي',
    'ؤ': 'و',
    'ة': 'ه',
    'ۀ': 'ه',
    'ك': 'ک',
    // Digit normalization (Arabic-Indic + Eastern Arabic-Indic)
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  String _normalizeSearchText(String value) {
    final lowered = value.trim().toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lowered.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_searchCharMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  bool _matchesSearch(ShopModel s, String q) {
    if (q.isEmpty) return true;
    final haystack = [
      s.name,
      s.phone ?? '',
      s.area ?? '',
      s.city ?? '',
      s.address ?? '',
      s.contactName ?? '',
      'r${s.routeNumber}',
      '${s.routeNumber}',
    ].map(_normalizeSearchText).join(' ');
    return haystack.contains(q);
  }

  List<ShopModel> _scopeShopsByRoute(List<ShopModel> shops) {
    if (_selectedRouteId == null) return shops;
    return shops.where((s) => s.routeId == _selectedRouteId).toList();
  }

  bool _matchesQuickFilter(ShopModel s, _ShopFlowStats flowStats) {
    switch (_filter) {
      case _ShopQuickFilter.collective:
        return true;
      case _ShopQuickFilter.iGave:
        return flowStats.cashOut > 0;
      case _ShopQuickFilter.iGot:
        return flowStats.cashIn > 0;
      case _ShopQuickFilter.iWillGet:
        return s.balance > 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final shopsAsync = user?.isSeller == true && user?.assignedRouteId != null
        ? ref.watch(shopsByRouteProvider(user!.assignedRouteId!))
        : ref.watch(shopsProvider);
    final transactionsAsync = ref.watch(shopsAnalyticsTransactionsProvider);
    final routesAsync = user?.isAdmin == true
        ? ref.watch(routesProvider)
        : null;
    final canCreateShop =
        user != null && (user.isAdmin || user.assignedRouteId != null);
    final scopedStatsShops = shopsAsync.value == null
        ? null
        : _scopeShopsByRoute(shopsAsync.value!);
    final flowByShop =
        scopedStatsShops == null || transactionsAsync.value == null
        ? null
        : _buildShopFlowStats(
            shops: scopedStatsShops,
            transactions: transactionsAsync.value!,
          );

    return Scaffold(
      body: Column(
        children: [
          // Export action row + search bar (combined)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchBar(
                    hintText: tr('search', ref),
                    onChanged: (v) =>
                        setState(() => _search = _normalizeSearchText(v)),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: tr('export_report', ref),
                  onSelected: (value) {
                    final shops = shopsAsync.value;
                    if (shops == null || shops.isEmpty) return;
                    final routes = routesAsync?.value ?? [];
                    if (value == 'all') {
                      _exportAllShops(shops, routes);
                    } else if (value == 'per_route') {
                      _exportPerRoute(shops, routes);
                    } else if (value == 'pdf_ledger') {
                      _showPdfExportDialog(shops, routes);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'all',
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart, size: 20),
                          const SizedBox(width: 8),
                          Text(tr('export_all_shops', ref)),
                        ],
                      ),
                    ),
                    if (user?.isAdmin == true)
                      PopupMenuItem(
                        value: 'per_route',
                        child: Row(
                          children: [
                            const Icon(Icons.route, size: 20),
                            const SizedBox(width: 8),
                            Text(tr('export_per_route', ref)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'pdf_ledger',
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf, size: 20),
                          const SizedBox(width: 8),
                          Text(tr('export_pdf_ledger', ref)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Route filter dropdown — admin only
          if (user?.isAdmin == true && routesAsync != null)
            routesAsync.when(
              data: (routes) {
                if (routes.length <= 1) return const SizedBox.shrink();
                final sorted = List.of(routes)
                  ..sort((a, b) => a.routeNumber.compareTo(b.routeNumber));
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr('filter_by_route', ref),
                      prefixIcon: const Icon(Icons.route, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedRouteId,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(tr('all_routes', ref)),
                          ),
                          ...sorted.map(
                            (r) => DropdownMenuItem<String?>(
                              value: r.id,
                              child: Text('${r.routeNumber} · ${r.name}'),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedRouteId = v),
                      ),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          // Stats strip — derived from the live shop list
          if (scopedStatsShops != null && flowByShop != null)
            _ShopStatsStrip(
              shops: scopedStatsShops,
              flowByShop: flowByShop,
              selected: _filter,
              onSelected: (f) => setState(() => _filter = f),
            )
          else
            const SizedBox.shrink(),
          Expanded(
            child: shopsAsync.when(
              data: (shops) {
                final scopedShops = _scopeShopsByRoute(shops);
                final scopedFlowByShop = _buildShopFlowStats(
                  shops: scopedShops,
                  transactions:
                      transactionsAsync.value ?? const <TransactionModel>[],
                );
                final filtered = scopedShops.where((s) {
                  final flowStats =
                      scopedFlowByShop[s.id] ?? const _ShopFlowStats();
                  return _matchesSearch(s, _search) &&
                      _matchesQuickFilter(s, flowStats);
                }).toList();

                switch (_filter) {
                  case _ShopQuickFilter.iGot:
                    filtered.sort(
                      (a, b) => (scopedFlowByShop[b.id]?.cashIn ?? 0).compareTo(
                        scopedFlowByShop[a.id]?.cashIn ?? 0,
                      ),
                    );
                  case _ShopQuickFilter.iGave:
                    filtered.sort(
                      (a, b) => (scopedFlowByShop[b.id]?.cashOut ?? 0)
                          .compareTo(scopedFlowByShop[a.id]?.cashOut ?? 0),
                    );
                  case _ShopQuickFilter.iWillGet:
                    filtered.sort((a, b) => b.balance.compareTo(a.balance));
                  case _ShopQuickFilter.collective:
                    break;
                }

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.store,
                    message: tr('no_shops', ref),
                  );
                }

                // Admin: grouped by route
                if (user?.isAdmin == true) {
                  final routes = routesAsync?.value ?? [];
                  if (routes.isNotEmpty) {
                    return _AdminGroupedShopsView(
                      shops: filtered,
                      routes: routes,
                      selectedFilter: _filter,
                      flowByShop: scopedFlowByShop,
                    );
                  }
                }

                // Detect duplicate shop names within the current list
                final nameCount = <String, int>{};
                for (final s in filtered) {
                  final k = s.name.toLowerCase();
                  nameCount[k] = (nameCount[k] ?? 0) + 1;
                }
                final duplicateNames = nameCount.entries
                    .where((e) => e.value > 1)
                    .map((e) => e.key)
                    .toSet();

                return AppPullRefresh(
                  onRefresh: () async {
                    if (user?.isSeller == true &&
                        user?.assignedRouteId != null) {
                      ref.invalidate(
                        shopsByRouteProvider(user!.assignedRouteId!),
                      );
                    } else {
                      ref.invalidate(shopsProvider);
                    }
                    await Future.delayed(const Duration(milliseconds: 300));
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ShopTile(
                      shop: filtered[i],
                      selectedFilter: _filter,
                      flowStats:
                          scopedFlowByShop[filtered[i].id] ??
                          const _ShopFlowStats(),
                      hasDuplicate: duplicateNames.contains(
                        filtered[i].name.toLowerCase(),
                      ),
                    ).listEntry(i),
                  ),
                );
              },
              loading: () => const ShimmerLoading(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () {
                  if (user?.isSeller == true && user?.assignedRouteId != null) {
                    ref.invalidate(
                      shopsByRouteProvider(user!.assignedRouteId!),
                    );
                  } else {
                    ref.invalidate(shopsProvider);
                  }
                },
              ),
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

  // ── Export helpers ──────────────────────────────────────────────────────

  void _exportAllShops(List<ShopModel> shops, List<RouteModel> routes) {
    final routeMap = {for (final r in routes) r.id: r};
    final headers = [
      tr('name', ref),
      tr('route', ref),
      tr('phone', ref),
      tr('area', ref),
      tr('balance', ref),
    ];
    final rows = shops.map((s) {
      final r = routeMap[s.routeId];
      return <dynamic>[
        s.name,
        r != null ? '${r.routeNumber} · ${r.name}' : '-',
        s.phone ?? '-',
        s.area ?? '-',
        s.balance,
      ];
    }).toList();
    ExportSheet.show(
      context,
      ref,
      title: tr('export_all_shops', ref),
      headers: headers,
      rows: rows,
      fileName: 'all_shops',
    );
  }

  void _exportPerRoute(List<ShopModel> shops, List<RouteModel> routes) {
    final routeMap = {for (final r in routes) r.id: r};
    final sorted = List.of(routes)
      ..sort((a, b) => a.routeNumber.compareTo(b.routeNumber));

    // Group shops by routeId
    final grouped = <String, List<ShopModel>>{};
    for (final s in shops) {
      grouped.putIfAbsent(s.routeId, () => []).add(s);
    }

    final headers = [
      tr('name', ref),
      tr('phone', ref),
      tr('area', ref),
      tr('balance', ref),
    ];

    // Build combined rows with route section headers
    final allRows = <List<dynamic>>[];
    for (final r in sorted) {
      final items = grouped[r.id];
      if (items == null || items.isEmpty) continue;
      // Insert route header as a separator row
      allRows.add(['── ${r.routeNumber} · ${r.name} ──', '', '', '']);
      for (final s in items) {
        allRows.add([s.name, s.phone ?? '-', s.area ?? '-', s.balance]);
      }
    }

    // Add unassigned shops
    final knownIds = routeMap.keys.toSet();
    final unassigned = shops
        .where((s) => !knownIds.contains(s.routeId))
        .toList();
    if (unassigned.isNotEmpty) {
      allRows.add(['── ${tr('shops_unassigned', ref)} ──', '', '', '']);
      for (final s in unassigned) {
        allRows.add([s.name, s.phone ?? '-', s.area ?? '-', s.balance]);
      }
    }

    ExportSheet.show(
      context,
      ref,
      title: tr('route_report', ref),
      headers: headers,
      rows: allRows,
      fileName: 'shops_per_route',
    );
  }

  // ── PDF Ledger export ───────────────────────────────────────────────────

  void _showPdfExportDialog(List<ShopModel> shops, List<RouteModel> routes) {
    String? selectedRouteId;
    final sorted = List.of(routes)
      ..sort((a, b) => a.routeNumber.compareTo(b.routeNumber));

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('export_pdf_ledger', ref)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('route', ref), style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: selectedRouteId,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.route, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(tr('all_routes', ref)),
                  ),
                  ...sorted.map(
                    (r) => DropdownMenuItem<String?>(
                      value: r.id,
                      child: Text('${r.routeNumber} · ${r.name}'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => selectedRouteId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr('cancel', ref)),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: Text(tr('confirm', ref)),
              onPressed: () {
                Navigator.of(ctx).pop();
                _generateMultiShopPdf(shops, routes, selectedRouteId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateMultiShopPdf(
    List<ShopModel> allShops,
    List<RouteModel> routes,
    String? routeId,
  ) async {
    // Show progress indicator
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(tr('generating_report', ref))),
          ],
        ),
      ),
    );

    try {
      final locale = ref.read(appLocaleProvider);
      final settings = await ref.read(settingsProvider.future);
      final user = ref.read(authUserProvider).value;

      // Fetch transactions
      final List<TransactionModel> txList;
      if (routeId != null) {
        txList = await ref.read(
          routeTransactionsExportProvider(routeId).future,
        );
      } else {
        txList = await ref.read(allTransactionsExportProvider.future);
      }

      // Build entryByMap
      final allUsers = user?.isAdmin == true
          ? await ref.read(allUsersProvider.future)
          : <UserModel>[];
      final entryByMap = <String, String>{
        for (final u in allUsers) u.id: u.displayName,
      };
      if (user != null) entryByMap[user.id] = user.displayName;

      // Group transactions by shopId for fast lookup
      final txByShop = <String, List<TransactionModel>>{};
      for (final tx in txList) {
        txByShop.putIfAbsent(tx.shopId, () => []).add(tx);
      }

      // Filter and sort shops
      final scopedShops = routeId != null
          ? allShops.where((s) => s.routeId == routeId).toList()
          : List.of(allShops);

      final routeMap = {for (final r in routes) r.id: r};
      final sortedRoutes = List.of(routes)
        ..sort((a, b) => a.routeNumber.compareTo(b.routeNumber));

      // Build sections: routes in order, shops alphabetically within each route
      final sections = <MultiShopLedgerSection>[];
      for (final route in sortedRoutes) {
        if (routeId != null && route.id != routeId) continue;
        final routeShops =
            scopedShops.where((s) => s.routeId == route.id).toList()
              ..sort((a, b) => a.name.compareTo(b.name));
        for (final shop in routeShops) {
          final shopTxs = txByShop[shop.id] ?? [];
          final netTx = shopTxs.fold<double>(
            0.0,
            (s, t) => s + t.balanceImpact,
          );
          sections.add(
            MultiShopLedgerSection(
              shopName: shop.name,
              routeLabel: '${route.routeNumber} · ${route.name}',
              openingBalance: shop.balance - netTx,
              transactions: shopTxs,
            ),
          );
        }
      }

      // Include shops with no route match
      final assignedIds = routeMap.keys.toSet();
      final unrouted =
          scopedShops.where((s) => !assignedIds.contains(s.routeId)).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      for (final shop in unrouted) {
        final shopTxs = txByShop[shop.id] ?? [];
        final netTx = shopTxs.fold<double>(0.0, (s, t) => s + t.balanceImpact);
        sections.add(
          MultiShopLedgerSection(
            shopName: shop.name,
            routeLabel: tr('shops_unassigned', ref),
            openingBalance: shop.balance - netTx,
            transactions: shopTxs,
          ),
        );
      }

      final routeName = routeId != null
          ? '${routeMap[routeId]?.routeNumber ?? ''} · ${routeMap[routeId]?.name ?? ''}'
          : tr('all_routes', ref);

      final labels = {
        'date': tr('date', ref),
        'description': tr('description', ref),
        'debit': tr('debit', ref),
        'credit': tr('credit', ref),
        'running_balance': tr('running_balance', ref),
        'account_statement': tr('account_statement', ref),
        'opening_balance': tr('opening_balance', ref),
        'net_payable': tr('net_payable', ref),
        'page': tr('page', ref),
        'report_date': tr('report_date', ref),
        'cash_in': tr('cash_in', ref),
        'cash_out': tr('cash_out', ref),
        'total_entries': tr('total_entries', ref),
        'generated_by': tr('generated_by', ref),
        'entry_by': tr('entry_by', ref),
        'name': tr('name', ref),
        'route': tr('route', ref),
        'all_routes': tr('all_routes', ref),
      };

      final bytes = await buildPdfMultiShopLedger(
        title: routeName,
        subtitle: tr('export_pdf_ledger', ref),
        companyName: settings.companyName,
        generatedBy: user?.displayName ?? '',
        sections: sections,
        labels: labels,
        locale: locale,
        logoBytes: settings.logoBytes,
        currency: settings.currency,
        showEntryBy: user?.isAdmin == true,
        entryByMap: entryByMap,
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final safeName = routeName.replaceAll(RegExp(r'[^\w]'), '_');
      await Printing.sharePdf(bytes: bytes, filename: 'ledger_$safeName.pdf');
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    }
  }
}

class _ShopFlowStats {
  final double cashIn;
  final double cashOut;

  const _ShopFlowStats({this.cashIn = 0, this.cashOut = 0});

  _ShopFlowStats add(TransactionModel tx) {
    if (tx.type == TransactionModel.typeCashIn) {
      return _ShopFlowStats(cashIn: cashIn + tx.amount, cashOut: cashOut);
    }
    if (tx.type == TransactionModel.typeCashOut) {
      return _ShopFlowStats(cashIn: cashIn, cashOut: cashOut + tx.amount);
    }
    return this;
  }
}

Map<String, _ShopFlowStats> _buildShopFlowStats({
  required Iterable<ShopModel> shops,
  required Iterable<TransactionModel> transactions,
}) {
  final shopIds = shops
      .map((s) => s.id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final flowByShop = <String, _ShopFlowStats>{
    for (final shopId in shopIds) shopId: const _ShopFlowStats(),
  };

  for (final tx in transactions) {
    final shopId = tx.shopId.trim();
    if (!shopIds.contains(shopId)) continue;
    flowByShop[shopId] = (flowByShop[shopId] ?? const _ShopFlowStats()).add(tx);
  }

  return flowByShop;
}

// ── Stats strip — CreditBook style ────────────────────────────────────────────

class _ShopStatsStrip extends ConsumerWidget {
  final List<ShopModel> shops;
  final Map<String, _ShopFlowStats> flowByShop;
  final _ShopQuickFilter selected;
  final ValueChanged<_ShopQuickFilter> onSelected;
  const _ShopStatsStrip({
    required this.shops,
    required this.flowByShop,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 700;
    final isSmallPhone = width < 360;

    final cardPadding = isTablet
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10)
        : isSmallPhone
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 6, vertical: 8);
    final valueFontSize = isTablet
        ? 13.0
        : isSmallPhone
        ? 10.0
        : 12.0;
    final labelFontSize = isTablet
        ? 11.0
        : isSmallPhone
        ? 9.0
        : 10.0;
    final iconSize = isTablet
        ? 18.0
        : isSmallPhone
        ? 14.0
        : 15.0;

    final totalGave = shops.fold(
      0.0,
      (sum, s) => sum + (flowByShop[s.id]?.cashOut ?? 0),
    );
    final totalGot = shops.fold(
      0.0,
      (sum, s) => sum + (flowByShop[s.id]?.cashIn ?? 0),
    );
    final totalWillGet = shops
        .where((s) => s.balance > 0)
        .fold(0.0, (sum, s) => sum + s.balance);
    final totalCollective = shops.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: _FilterStatCard(
              icon: Icons.arrow_circle_down,
              label: tr('i_got', ref),
              value: AppFormatters.sar(totalGot),
              color: AppTheme.clearFg(cs),
              selected: selected == _ShopQuickFilter.iGot,
              onTap: () => onSelected(_ShopQuickFilter.iGot),
              contentPadding: cardPadding,
              iconSize: iconSize,
              labelFontSize: labelFontSize,
              valueFontSize: valueFontSize,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _FilterStatCard(
              icon: Icons.arrow_circle_up,
              label: tr('i_gave', ref),
              value: AppFormatters.sar(totalGave),
              color: AppTheme.debtFg(cs),
              selected: selected == _ShopQuickFilter.iGave,
              onTap: () => onSelected(_ShopQuickFilter.iGave),
              contentPadding: cardPadding,
              iconSize: iconSize,
              labelFontSize: labelFontSize,
              valueFontSize: valueFontSize,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _FilterStatCard(
              icon: Icons.schedule,
              label: tr('i_will_get', ref),
              value: AppFormatters.sar(totalWillGet),
              color: totalWillGet >= 0
                  ? AppTheme.warningFg(cs)
                  : AppTheme.debtFg(cs),
              selected: selected == _ShopQuickFilter.iWillGet,
              onTap: () => onSelected(_ShopQuickFilter.iWillGet),
              contentPadding: cardPadding,
              iconSize: iconSize,
              labelFontSize: labelFontSize,
              valueFontSize: valueFontSize,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _FilterStatCard(
              icon: Icons.grid_view,
              label: tr('collective', ref),
              value: '$totalCollective',
              color: cs.primary,
              selected: selected == _ShopQuickFilter.collective,
              onTap: () => onSelected(_ShopQuickFilter.collective),
              contentPadding: cardPadding,
              iconSize: iconSize,
              labelFontSize: labelFontSize,
              valueFontSize: valueFontSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final EdgeInsets contentPadding;
  final double iconSize;
  final double labelFontSize;
  final double valueFontSize;
  const _FilterStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.contentPadding,
    required this.iconSize,
    required this.labelFontSize,
    required this.valueFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: contentPadding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: iconSize, color: color),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: valueFontSize,
                  color: color,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: labelFontSize,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ShopQuickFilter { collective, iGot, iGave, iWillGet }

class _ShopTile extends ConsumerWidget {
  final ShopModel shop;
  final _ShopQuickFilter selectedFilter;
  final _ShopFlowStats flowStats;
  final bool hasDuplicate;
  const _ShopTile({
    required this.shop,
    required this.selectedFilter,
    required this.flowStats,
    this.hasDuplicate = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDebt = shop.balance > 0;
    final hasCredit = shop.balance < 0;
    final cs = Theme.of(context).colorScheme;
    final (
      trailingAmount,
      trailingLabel,
      trailingColor,
    ) = switch (selectedFilter) {
      _ShopQuickFilter.iGot => (
        flowStats.cashIn,
        tr('i_got', ref),
        AppTheme.clearFg(cs),
      ),
      _ShopQuickFilter.iGave => (
        flowStats.cashOut,
        tr('i_gave', ref),
        AppTheme.debtFg(cs),
      ),
      _ShopQuickFilter.iWillGet => (
        shop.balance > 0 ? shop.balance : 0.0,
        tr('i_will_get', ref),
        AppTheme.debtFg(cs),
      ),
      _ShopQuickFilter.collective when hasDebt => (
        shop.balance.abs(),
        tr('i_will_get', ref),
        AppTheme.debtFg(cs),
      ),
      _ShopQuickFilter.collective when hasCredit => (
        shop.balance.abs(),
        tr('i_got', ref),
        AppTheme.clearFg(cs),
      ),
      _ShopQuickFilter.collective => (
        0.0,
        tr('clear', ref),
        AppTheme.clearFg(cs),
      ),
    };

    return Card(
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: hasDebt
                  ? AppTheme.debtBg(cs)
                  : AppTheme.clearBg(cs),
              child: Icon(
                Icons.store,
                color: hasDebt ? AppTheme.debtFg(cs) : AppTheme.clearFg(cs),
              ),
            ),
            if (hasDuplicate)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppTheme.warningFg(cs),
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 1.5),
                  ),
                  child: Icon(
                    Icons.priority_high,
                    size: 12,
                    color: cs.onInverseSurface,
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          shop.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (shop.phone != null) shop.phone,
            '${shop.routeNumber}',
            if (shop.area != null) shop.area,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Show the amount that matches the selected analytics chip.
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AppFormatters.sar(trailingAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: trailingColor,
              ),
            ),
            Text(
              trailingLabel,
              style: TextStyle(fontSize: 10, color: trailingColor),
            ),
          ],
        ),
        onTap: () => context.push('/shops/${shop.id}'),
      ),
    );
  }
}

// ── Admin grouped view ────────────────────────────────────────────────────────

class _AdminGroupedShopsView extends ConsumerStatefulWidget {
  final List<ShopModel> shops;
  final List<RouteModel> routes;
  final _ShopQuickFilter selectedFilter;
  final Map<String, _ShopFlowStats> flowByShop;
  const _AdminGroupedShopsView({
    required this.shops,
    required this.routes,
    required this.selectedFilter,
    required this.flowByShop,
  });

  @override
  ConsumerState<_AdminGroupedShopsView> createState() =>
      _AdminGroupedShopsViewState();
}

class _AdminGroupedShopsViewState
    extends ConsumerState<_AdminGroupedShopsView> {
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
    final unassigned = widget.shops
        .where((s) => !knownIds.contains(s.routeId))
        .toList();
    if (unassigned.isNotEmpty) {
      sections.add((route: null, key: '__unassigned', items: unassigned));
    }

    if (sections.isEmpty) {
      return EmptyState(
        icon: Icons.store,
        message: tr('msg_no_shops_found', ref),
      );
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
                          ? '${r.routeNumber} · ${r.name}'
                          : tr('shops_unassigned', ref),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (r?.assignedSellerName != null)
                    Text(
                      r!.assignedSellerName!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: 8),
                  // Per-route outstanding balance
                  Builder(
                    builder: (_) {
                      final routeOutstanding = section.items
                          .where((s) => s.balance > 0)
                          .fold(0.0, (sum, s) => sum + s.balance);
                      if (routeOutstanding > 0) {
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.debtBg(cs),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppFormatters.sar(routeOutstanding),
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
                    },
                  ),
                  Text(
                    '${section.items.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // Detect duplicates within the section
        final sectionNames = <String, int>{};
        for (final s in section.items) {
          final k = s.name.toLowerCase();
          sectionNames[k] = (sectionNames[k] ?? 0) + 1;
        }
        final shop = section.items[entry.itemIdx];
        return _ShopTile(
          shop: shop,
          selectedFilter: widget.selectedFilter,
          flowStats: widget.flowByShop[shop.id] ?? const _ShopFlowStats(),
          hasDuplicate: (sectionNames[shop.name.toLowerCase()] ?? 0) > 1,
        );
      },
    );
  }
}
