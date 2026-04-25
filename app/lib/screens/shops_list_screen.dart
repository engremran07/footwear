import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/name_resolver.dart';
import '../core/utils/formatters.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/report_column_naming.dart';
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
import '../widgets/whatsapp_button.dart';

class ShopsListScreen extends ConsumerStatefulWidget {
  /// When non-null, pre-filters shops to those belonging to routes with this
  /// currency (e.g. 'PKR' or 'SAR') and auto-enables the Outstanding filter.
  final String? filterCurrency;

  const ShopsListScreen({super.key, this.filterCurrency});

  @override
  ConsumerState<ShopsListScreen> createState() => _ShopsListScreenState();
}

class _ShopsListScreenState extends ConsumerState<ShopsListScreen> {
  String _search = '';
  _ShopQuickFilter _filter = _ShopQuickFilter.collective;
  String? _selectedRouteId;

  @override
  void initState() {
    super.initState();
    // When navigated from the outstanding dashboard card, pre-select
    // the outstanding filter so the user immediately sees debtors.
    if (widget.filterCurrency != null) {
      _filter = _ShopQuickFilter.iWillGet;
    }
  }

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

  // Cache normalized haystack per shop ID to avoid re-computing on every
  // keystroke for every shop in the list.
  final Map<String, String> _haystackCache = {};

  String _shopHaystack(ShopModel s) {
    return _haystackCache.putIfAbsent(s.id, () {
      return [
        s.name,
        s.phone ?? '',
        s.area ?? '',
        s.city ?? '',
        s.address ?? '',
        s.contactName ?? '',
        'r${s.routeNumber}',
        '${s.routeNumber}',
      ].map(_normalizeSearchText).join(' ');
    });
  }

  bool _matchesSearch(ShopModel s, String q) {
    if (q.isEmpty) return true;
    return _shopHaystack(s).contains(q);
  }

  List<ShopModel> _scopeShopsByRoute(
    List<ShopModel> shops, {
    Set<String>? currencyRouteIds,
  }) {
    if (currencyRouteIds != null) {
      var filtered = shops.where((s) => currencyRouteIds.contains(s.routeId));
      if (_selectedRouteId != null) {
        filtered = filtered.where((s) => s.routeId == _selectedRouteId);
      }
      return filtered.toList();
    }
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
      case _ShopQuickFilter.activityToday:
        return _isToday(s.lastTransactionAt?.toDate());
    }
  }

  static bool _isToday(DateTime? dt) {
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final isSeller = user?.isSeller == true;
    final sellerRouteIds = user?.assignedRouteIds ?? [];

    // Seller sees shops from ALL assigned routes; admin sees all shops.
    final shopsAsync = isSeller && sellerRouteIds.isNotEmpty
        ? ref.watch(sellerAllShopsProvider)
        : ref.watch(shopsProvider);
    final transactionsAsync = ref.watch(shopsAnalyticsTransactionsProvider);
    final routesAsync = user?.isAdmin == true
        ? ref.watch(routesProvider)
        : (isSeller && sellerRouteIds.isNotEmpty
              ? ref.watch(routesBySellerProvider(user!.id))
              : null);
    final canCreateShop =
        user != null && (user.isAdmin || sellerRouteIds.isNotEmpty);

    // When navigated with ?currency=X, restrict shops to routes of that currency.
    final filterCurrency = widget.filterCurrency?.toUpperCase();
    final currencyRouteIds =
        (filterCurrency != null && routesAsync?.value != null)
        ? routesAsync!.value!
              .where((r) => r.currency.toUpperCase() == filterCurrency)
              .map((r) => r.id)
              .toSet()
        : null;

    final scopedStatsShops = shopsAsync.value == null
        ? null
        : _scopeShopsByRoute(
            shopsAsync.value!,
            currencyRouteIds: currencyRouteIds,
          );
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
          // Currency filter active banner
          if (filterCurrency != null)
            Container(
              color: AppBrand.warningColor.withAlpha(20),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt,
                    size: 16,
                    color: AppBrand.warningColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$filterCurrency ${tr('outstanding_balance', ref).toLowerCase()}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppBrand.warningColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/shops'),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppBrand.warningColor,
                    ),
                  ),
                ],
              ),
            ),
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
          // Route filter dropdown — admin and multi-route sellers
          if (routesAsync != null)
            routesAsync.when(
              skipLoadingOnRefresh: true,
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
              skipLoadingOnRefresh: true,
              data: (shops) {
                final scopedShops = _scopeShopsByRoute(
                  shops,
                  currencyRouteIds: currencyRouteIds,
                );
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
                  case _ShopQuickFilter.activityToday:
                    // Sort by last transaction time DESC (null = least recent)
                    filtered.sort((a, b) {
                      final ta = a.lastTransactionAt;
                      final tb = b.lastTransactionAt;
                      if (ta == null && tb == null) {
                        return a.name.compareTo(b.name);
                      }
                      if (ta == null) return 1;
                      if (tb == null) return -1;
                      return tb.compareTo(ta);
                    });
                }

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.store,
                    message: tr('no_shops', ref),
                  );
                }

                // Group by route for admin and sellers with multiple routes.
                final routes = routesAsync?.value ?? [];
                final shouldGroupByRoute =
                    user?.isAdmin == true || routes.length > 1;
                if (shouldGroupByRoute && routes.isNotEmpty) {
                  return _AdminGroupedShopsView(
                    shops: filtered,
                    routes: routes,
                    selectedFilter: _filter,
                    flowByShop: scopedFlowByShop,
                    showAssignedSellerNames: user?.isAdmin == true,
                  );
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

                // Pre-compute currency per routeId to avoid N per-tile
                // provider subscriptions (prevents re-subscription flicker).
                final currencyByRoute = <String, String>{
                  for (final r in routes) r.id: r.currency,
                };

                return AppPullRefresh(
                  onRefresh: () async {
                    // sellerAllShopsProvider is a live Firestore stream —
                    // it auto-updates; invalidating it forces a cold-start
                    // reload that shows the full shimmer unnecessarily.
                    await Future.delayed(const Duration(milliseconds: 300));
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ShopTile(
                      shop: filtered[i],
                      selectedFilter: _filter,
                      flowStats:
                          scopedFlowByShop[filtered[i].id] ??
                          const _ShopFlowStats(),
                      currency: currencyByRoute[filtered[i].routeId] ?? 'SAR',
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
                  if (isSeller && sellerRouteIds.isNotEmpty) {
                    ref.invalidate(sellerAllShopsProvider);
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
      triCol('name'),
      triCol('route'),
      triCol('phone'),
      triCol('area'),
      triCol('balance'),
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
      fileName: AppFormatters.exportFileName(ExportNames.shopsAll),
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
      triCol('name'),
      triCol('phone'),
      triCol('area'),
      triCol('balance'),
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
      fileName: AppFormatters.exportFileName(ExportNames.shopsPerRoute),
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

  bool _generatingPdf = false;

  Future<void> _generateMultiShopPdf(
    List<ShopModel> allShops,
    List<RouteModel> routes,
    String? routeId,
  ) async {
    if (_generatingPdf) return;
    _generatingPdf = true;
    var progressDismissed = false;

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
      // Use .future to await first auth emission instead of reading a
      // potentially-null .value while the StreamProvider is still loading.
      final user = await ref.read(authUserProvider.future);

      // Invalidate export providers to ensure fresh data, then read.
      // These are NOT autoDispose — they persist until invalidated.
      final List<TransactionModel> txList;
      if (routeId != null) {
        ref.invalidate(routeTransactionsExportProvider(routeId));
        txList = await ref.read(
          routeTransactionsExportProvider(routeId).future,
        );
      } else {
        ref.invalidate(allTransactionsExportProvider);
        txList = await ref.read(allTransactionsExportProvider.future);
      }

      // Build entryByMap — allUsersExportProvider includes deactivated
      // sellers so historical transactions still resolve to display names.
      ref.invalidate(allUsersExportProvider);
      final allUsers = user?.isAdmin == true
          ? await ref.read(allUsersExportProvider.future)
          : <UserModel>[];
      final names = NameResolver(
        users: allUsers,
        extra: {if (user != null) user.id: user.displayName},
        unknownLabel: trRead('unknown_user', locale),
      );

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

      final labels = trilingualLabels({
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
      });

      // Flatten transactions into rows for Excel export
      final excelHeaders = [
        triCol('name'),
        triCol('route'),
        triCol('date'),
        triCol('description'),
        triCol('debit'),
        triCol('credit'),
      ];
      final excelRows = <List<String>>[];
      for (final section in sections) {
        for (final tx in section.transactions) {
          final isDebit = tx.balanceImpact > 0;
          excelRows.add([
            section.shopName,
            section.routeLabel,
            AppFormatters.dateOnly(tx.createdAt.toDate()),
            tx.description ?? '',
            isDebit ? tx.amount.toStringAsFixed(2) : '',
            !isDebit ? tx.amount.toStringAsFixed(2) : '',
          ]);
        }
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        progressDismissed = true;
      }

      if (!mounted) return;

      // Show ExportSheet with all export options
      ExportSheet.show(
        context,
        ref,
        title: routeName,
        headers: excelHeaders,
        rows: excelRows,
        fileName: AppFormatters.exportFileName(ExportNames.ledger, routeName),
        subtitle: tr('export_pdf_ledger', ref),
        pdfBytesBuilder: () => buildPdfMultiShopLedger(
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
          entryByMap: names.map,
        ),
      );
    } catch (e, st) {
      debugPrint('MultiShopPdf export error: $e\n$st');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'multi-shop PDF export',
      );
      if (mounted) {
        if (!progressDismissed) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      _generatingPdf = false;
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
    final now = DateTime.now();
    final totalActivityToday = shops.where((s) {
      final dt = s.lastTransactionAt?.toDate();
      if (dt == null) return false;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: _FilterStatCard(
              icon: Icons.arrow_circle_down,
              label: tr('i_got', ref),
              value: AppFormatters.compact(totalGot),
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
              value: AppFormatters.compact(totalGave),
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
              value: AppFormatters.compact(totalWillGet),
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
          const SizedBox(width: 6),
          Expanded(
            child: _FilterStatCard(
              icon: Icons.today,
              label: tr('activity_today', ref),
              value: '$totalActivityToday',
              color: AppBrand.successColor,
              selected: selected == _ShopQuickFilter.activityToday,
              onTap: () => onSelected(_ShopQuickFilter.activityToday),
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

enum _ShopQuickFilter { collective, iGot, iGave, iWillGet, activityToday }

class _ShopTile extends ConsumerWidget {
  final ShopModel shop;
  final _ShopQuickFilter selectedFilter;
  final _ShopFlowStats flowStats;
  final bool hasDuplicate;
  final String currency;
  const _ShopTile({
    required this.shop,
    required this.selectedFilter,
    required this.flowStats,
    required this.currency,
    this.hasDuplicate = false,
  });

  bool get _isActivityToday {
    final dt = shop.lastTransactionAt?.toDate();
    if (dt == null) return false;
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

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
      _ShopQuickFilter.activityToday when hasDebt => (
        shop.balance.abs(),
        tr('i_will_get', ref),
        AppTheme.debtFg(cs),
      ),
      _ShopQuickFilter.activityToday when hasCredit => (
        shop.balance.abs(),
        tr('i_got', ref),
        AppTheme.clearFg(cs),
      ),
      _ShopQuickFilter.activityToday => (
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
            // "Today" activity badge
            if (_isActivityToday)
              Positioned(
                bottom: -4,
                left: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppBrand.successColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.surface, width: 1),
                  ),
                  child: Text(
                    tr('today', ref),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WhatsAppShopCtaButton(
              shop: shop,
              iconSize: 20,
              onViewStatement: () => context.push('/shops/${shop.id}'),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppFormatters.currency(trailingAmount, currency),
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
  final bool showAssignedSellerNames;
  const _AdminGroupedShopsView({
    required this.shops,
    required this.routes,
    required this.selectedFilter,
    required this.flowByShop,
    this.showAssignedSellerNames = true,
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
      padding: const EdgeInsets.only(bottom: 88),
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
                  if (widget.showAssignedSellerNames &&
                      (r?.assignedSellerNames.isNotEmpty ?? false))
                    Text(
                      r!.assignedSellerNames.join(', '),
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
                              AppFormatters.currency(
                                routeOutstanding,
                                r?.currency ?? 'SAR',
                              ),
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
          currency: section.route?.currency ?? 'SAR',
          hasDuplicate: (sectionNames[shop.name.toLowerCase()] ?? 0) > 1,
        );
      },
    );
  }
}
