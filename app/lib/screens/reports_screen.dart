import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../providers/dashboard_provider.dart';
import '../providers/product_provider.dart';
import '../providers/route_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/export_sheet.dart';
import '../widgets/error_state.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  void _showNoData(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(infoSnackBar(tr('no_data', ref)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authUserProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final ppc = ref.watch(settingsProvider).value?.pairsPerCarton ?? 12;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          stats.when(
            data: (s) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('summary', ref),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _Row(
                        label: tr('total_routes', ref),
                        value: '${s.totalRoutes}',
                      ),
                      _Row(
                        label: tr('total_shops', ref),
                        value: '${s.totalShops}',
                      ),
                      _Row(
                        label: tr('outstanding_balance', ref),
                        value: () {
                          final parts = s.currencyStats.entries
                              .where((e) => e.value.outstanding != 0)
                              .map(
                                (e) => AppFormatters.currency(
                                  e.value.outstanding,
                                  e.key,
                                ),
                              )
                              .toList();
                          return parts.isEmpty
                              ? AppFormatters.currency(0)
                              : parts.join(' / ');
                        }(),
                      ),
                      _Row(
                        label: tr('total_products', ref),
                        value: '${s.totalProducts}',
                      ),
                      _Row(
                        label: tr('total_variants', ref),
                        value: '${s.totalVariants}',
                      ),
                      _Row(
                        label: tr('stock_pairs', ref),
                        value: AppFormatters.stock(s.totalStockPairs, ppc),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => mappedErrorState(
              error: e,
              ref: ref,
              onRetry: () => ref.invalidate(dashboardStatsProvider),
            ),
          ),
          const SizedBox(height: 16),
          // Outstanding Top Debtors
          _OutstandingTopDebtors(),
          const SizedBox(height: 16),
          // Export sections
          _ExportCard(
            icon: Icons.storefront,
            title: tr('shops_report', ref),
            onExport: () => _exportShops(context, ref),
          ),
          _ExportCard(
            icon: Icons.inventory_2,
            title: tr('inventory_report', ref),
            onExport: () => _exportInventory(context, ref, ppc),
          ),
          _ExportCard(
            icon: Icons.receipt_long,
            title: tr('transactions_report', ref),
            onExport: () => _exportTransactions(context, ref),
          ),
          _ExportCard(
            icon: Icons.account_balance_wallet,
            title: tr('outstanding_report', ref),
            onExport: () => _exportOutstanding(context, ref),
          ),
          _ExportCard(
            icon: Icons.money_off,
            title: tr('bad_debts_report', ref),
            onExport: () => _exportBadDebts(context, ref),
          ),
          const _AccountStatementCard(),
          const _SellerReportCard(),
        ],
      ).screenEntry(),
    );
  }

  Future<void> _exportShops(BuildContext context, WidgetRef ref) async {
    final user = await ref.read(authUserProvider.future);
    if (!context.mounted) return;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final shops = user.isAdmin
        ? ref.read(shopsProvider).value ?? <ShopModel>[]
        : (user.assignedRouteIds.isNotEmpty
              ? ref.read(sellerAllShopsProvider).value ?? <ShopModel>[]
              : <ShopModel>[]);
    if (shops.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('shops_report', ref);
    final headers = [
      tr('name', ref),
      tr('route', ref),
      tr('phone', ref),
      tr('area', ref),
      tr('city', ref),
      tr('balance', ref),
    ];
    final routeCurrencyMap = <String, String>{
      for (final r in ref.read(routesProvider).value ?? <RouteModel>[])
        r.id: r.currency,
    };
    final rows = shops
        .map(
          (s) => [
            s.name,
            '${s.routeNumber}',
            s.phone ?? '',
            s.area ?? '',
            s.city ?? '',
            AppFormatters.currency(
              s.balance,
              routeCurrencyMap[s.routeId] ?? 'SAR',
            ),
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: AppFormatters.exportFileName(ExportNames.shopsReport),
    );
  }

  Future<void> _exportInventory(
    BuildContext context,
    WidgetRef ref,
    int ppc,
  ) async {
    final user = await ref.read(authUserProvider.future);
    if (!context.mounted) return;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final rows = user.isAdmin
        ? (ref.read(allVariantsProvider).value ?? [])
              .map(
                (v) => [
                  v.variantName,
                  AppFormatters.stock(v.quantityAvailable, ppc),
                ],
              )
              .toList()
        : (ref.read(sellerInventoryProvider(user.id)).value ?? [])
              .map(
                (v) => [
                  v.variantName,
                  AppFormatters.stock(v.quantityAvailable, ppc),
                ],
              )
              .toList();
    if (rows.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('inventory_report', ref);
    final headers = [tr('variant_name', ref), tr('stock_pairs', ref)];
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: AppFormatters.exportFileName(ExportNames.inventoryReport),
    );
  }

  Future<void> _exportTransactions(BuildContext context, WidgetRef ref) async {
    final user = await ref.read(authUserProvider.future);
    if (!context.mounted) return;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final txs = user.isAdmin
        ? ref.read(allTransactionsProvider).value ?? []
        : ref.read(sellerTransactionsProvider(user.id)).value ?? [];
    if (txs.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('transactions_report', ref);
    final headers = [
      tr('date', ref),
      tr('shop_name', ref),
      tr('type', ref),
      tr('amount', ref),
      tr('description', ref),
    ];
    final rows = txs
        .map(
          (t) => [
            AppFormatters.dateTime(t.createdAt),
            t.shopName,
            t.type == 'cash_in' ? tr('cash_in', ref) : tr('cash_out', ref),
            AppFormatters.currency(t.amount),
            t.description ?? '',
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: AppFormatters.exportFileName(ExportNames.transactionsReport),
    );
  }

  Future<void> _exportOutstanding(BuildContext context, WidgetRef ref) async {
    final user = await ref.read(authUserProvider.future);
    if (!context.mounted) return;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final shops = user.isAdmin
        ? ref.read(outstandingShopsProvider).value ?? <ShopModel>[]
        : (user.assignedRouteIds.isNotEmpty
              ? ref
                        .read(sellerAllShopsProvider)
                        .value
                        ?.where((s) => s.balance > 0)
                        .toList() ??
                    <ShopModel>[]
              : <ShopModel>[]);
    if (shops.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('outstanding_report', ref);
    final headers = [
      tr('name', ref),
      tr('route', ref),
      tr('phone', ref),
      tr('balance', ref),
    ];
    final routeCurrencyMap2 = <String, String>{
      for (final r in ref.read(routesProvider).value ?? <RouteModel>[])
        r.id: r.currency,
    };
    final rows = shops
        .map(
          (s) => [
            s.name,
            '${s.routeNumber}',
            s.phone ?? '',
            AppFormatters.currency(
              s.balance,
              routeCurrencyMap2[s.routeId] ?? 'SAR',
            ),
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: AppFormatters.exportFileName(ExportNames.outstandingReport),
    );
  }

  Future<void> _exportBadDebts(BuildContext context, WidgetRef ref) async {
    final user = await ref.read(authUserProvider.future);
    if (!context.mounted) return;
    if (user == null) {
      _showNoData(context, ref);
      return;
    }
    final shops = user.isAdmin
        ? ref.read(shopsProvider).value ?? <ShopModel>[]
        : (user.assignedRouteIds.isNotEmpty
              ? ref.read(sellerAllShopsProvider).value ?? <ShopModel>[]
              : <ShopModel>[]);
    final badDebtShops = shops.where((s) => s.badDebt).toList();
    if (badDebtShops.isEmpty) {
      _showNoData(context, ref);
      return;
    }
    final title = tr('bad_debts_report', ref);
    final headers = [
      tr('name', ref),
      tr('phone', ref),
      tr('bad_debt_amount', ref),
      tr('date', ref),
    ];
    final routeCurrencyMap3 = <String, String>{
      for (final r in ref.read(routesProvider).value ?? <RouteModel>[])
        r.id: r.currency,
    };
    final rows = badDebtShops
        .map(
          (s) => [
            s.name,
            s.phone ?? '',
            AppFormatters.currency(
              s.badDebtAmount,
              routeCurrencyMap3[s.routeId] ?? 'SAR',
            ),
            s.badDebtDate != null ? AppFormatters.dateTime(s.badDebtDate!) : '',
          ],
        )
        .toList();
    ExportSheet.show(
      context,
      ref,
      title: title,
      headers: headers,
      rows: rows,
      fileName: AppFormatters.exportFileName(ExportNames.badDebtsReport),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onExport;
  const _ExportCard({
    required this.icon,
    required this.title,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.download),
        onTap: onExport,
      ),
    );
  }
}

// ─── Outstanding Top Debtors Ranked List ────────────────────────────────────

class _OutstandingTopDebtors extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    final shopsAsync = user?.isAdmin == true
        ? ref.watch(shopsProvider)
        : ref.watch(sellerAllShopsProvider);

    return shopsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (shops) {
        final withDebt = shops.where((s) => s.balance > 0).toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
        if (withDebt.isEmpty) return const SizedBox.shrink();

        final top = withDebt.take(10).toList();
        final maxBalance = top.first.balance;
        final cs = Theme.of(context).colorScheme;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('top_outstanding', ref),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...top.asMap().entries.map((entry) {
                  final i = entry.key;
                  final shop = entry.value;
                  final ratio = maxBalance > 0
                      ? shop.balance / maxBalance
                      : 0.0;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context.push('/shops/${shop.id}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    shop.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppFormatters.currency(
                                    shop.balance,
                                    ref.watch(
                                      routeCurrencyProvider(shop.routeId),
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.debtFg(cs),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 5,
                                backgroundColor: cs.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.debtFg(cs).withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Account Statement Card ────────────────────────────────────────────────
// â”€â”€â”€ Account Statement Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _AccountStatementCard extends ConsumerStatefulWidget {
  const _AccountStatementCard();
  @override
  ConsumerState<_AccountStatementCard> createState() =>
      _AccountStatementCardState();
}

class _AccountStatementCardState extends ConsumerState<_AccountStatementCard> {
  String? _selectedShopId;
  bool _generating = false;

  String _transactionTypeLabel(TransactionModel tx) {
    return switch (tx.type) {
      TransactionModel.typeCashIn => tr('cash_in', ref),
      TransactionModel.typeCashOut => tr('cash_out', ref),
      TransactionModel.typeReturn => tr('return', ref),
      'write_off' => tr('write_off', ref),
      _ => tx.type.replaceAll('_', ' '),
    };
  }

  Map<String, String> _labels(WidgetRef ref) {
    final keys = [
      'date',
      'description',
      'sale_type',
      'debit',
      'credit',
      'running_balance',
      'account_statement',
      'opening_balance',
      'net_payable',
      'shop',
      'seller',
      'total',
      'page',
      'report_date',
      'entry_by',
      'mode',
      'cash_in',
      'cash_out',
      'total_entries',
      'generated_by',
      'duration',
    ];
    return {for (final k in keys) k: tr(k, ref)};
  }

  Future<void> _generate() async {
    if (_selectedShopId == null) return;
    setState(() => _generating = true);
    try {
      final locale = ref.read(appLocaleProvider);
      final user = await ref.read(authUserProvider.future);
      if (!context.mounted) return;
      final shops = user?.isAdmin == true
          ? ref.read(shopsProvider).value ?? <ShopModel>[]
          : (user?.assignedRouteIds.isNotEmpty == true
                ? ref.read(sellerAllShopsProvider).value ?? <ShopModel>[]
                : <ShopModel>[]);
      final shop = shops.firstWhere((s) => s.id == _selectedShopId);

      ref.invalidate(shopTransactionsExportProvider(_selectedShopId!));
      final txs = await ref.read(
        shopTransactionsExportProvider(_selectedShopId!).future,
      );

      final settings = await ref.read(settingsProvider.future);
      // allUsersExportProvider: no active filter, one-shot .get() â€”
      // covers deactivated sellers; avoids autoDispose cached-value race.
      ref.invalidate(allUsersExportProvider);
      final allUsers = user?.isAdmin == true
          ? await ref.read(allUsersExportProvider.future)
          : <UserModel>[];
      final names = NameResolver(
        users: allUsers,
        extra: {if (user != null) user.id: user.displayName},
        unknownLabel: trRead('unknown_user', locale),
      );

      // Reconcile opening balance so the final running balance equals
      // the stored customer.balance regardless of transaction-count limits.
      final netTx = txs.fold<double>(0.0, (s, t) => s + t.balanceImpact);
      final labels = applyArabicColumnNamesToLabels(
        _labels(ref),
        locale: locale,
        enabled: settings.showArabicColumnNamesInEnglishReports,
      );
      final openingBalance = shop.balance - netTx;
      final acctCurrency = ref.read(routeCurrencyProvider(shop.routeId));

      if (!context.mounted) return;
      ExportSheet.show(
        // ignore: use_build_context_synchronously
        context,
        ref,
        title: '${shop.name} - ${tr('account_statement', ref)}',
        headers: [
          tr('date', ref),
          tr('type', ref),
          tr('amount', ref),
          tr('description', ref),
        ],
        rows: txs
            .map(
              (t) => [
                AppFormatters.dateTime(t.createdAt),
                _transactionTypeLabel(t),
                AppFormatters.currency(t.amount, acctCurrency),
                t.description ?? '',
              ],
            )
            .toList(),
        fileName: AppFormatters.exportFileName(ExportNames.ledger, shop.name),
        pdfBytesBuilder: () => buildPdfLedger(
          shopName: shop.name,
          companyName: settings.companyName,
          generatedBy: user?.displayName ?? '',
          openingBalance: openingBalance,
          transactions: txs,
          entryByMap: names.map,
          showEntryBy: true,
          dateFrom: txs.isNotEmpty ? txs.first.createdAt.toDate() : null,
          dateTo: txs.isNotEmpty ? txs.last.createdAt.toDate() : null,
          labels: labels,
          locale: locale,
          currency: settings.currency,
          logoBytes: settings.logoBytes,
        ),
      );
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final AsyncValue<List<ShopModel>> shopsAsync = user?.isAdmin == true
        ? ref.watch(shopsProvider)
        : (user?.assignedRouteIds.isNotEmpty == true
              ? ref.watch(sellerAllShopsProvider)
              : const AsyncData(<ShopModel>[]));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('account_statement', ref),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            shopsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () {
                  if (user?.isAdmin == true) {
                    ref.invalidate(shopsProvider);
                  } else if (user?.assignedRouteIds.isNotEmpty == true) {
                    ref.invalidate(sellerAllShopsProvider);
                  }
                },
              ),
              data: (shops) => DropdownButtonFormField<String>(
                initialValue: _selectedShopId,
                decoration: InputDecoration(
                  labelText: tr('shop', ref),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: shops
                    .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedShopId = v),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedShopId == null || _generating
                    ? null
                    : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(tr('export', ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ Seller Report Card (admin only) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SellerReportCard extends ConsumerStatefulWidget {
  const _SellerReportCard();
  @override
  ConsumerState<_SellerReportCard> createState() => _SellerReportCardState();
}

class _SellerReportCardState extends ConsumerState<_SellerReportCard> {
  String? _selectedSellerId;
  bool _generating = false;

  Map<String, String> _labels(WidgetRef ref) {
    final keys = [
      'seller_report',
      'seller',
      'route',
      'inventory',
      'shops',
      'shop',
      'stock_sold',
      'stock_received',
      'stock_remaining',
      'revenue',
      'outstanding',
      'total',
      'pairs',
      'report_date',
      'page',
    ];
    return {for (final k in keys) k: tr(k, ref)};
  }

  Future<void> _generate() async {
    if (_selectedSellerId == null) return;
    setState(() => _generating = true);
    try {
      final locale = ref.read(appLocaleProvider);

      // Use export providers (one-shot .get()) so data is always fresh and
      // complete, regardless of whether stream providers are currently active.
      ref.invalidate(allUsersExportProvider);
      final users = await ref.read(allUsersExportProvider.future);
      final seller = users.firstWhere(
        (u) => u.id == _selectedSellerId,
        orElse: () => throw StateError('Seller not found: $_selectedSellerId'),
      );

      ref.invalidate(sellerTransactionsExportProvider(_selectedSellerId!));
      final allTxs = await ref.read(
        sellerTransactionsExportProvider(_selectedSellerId!).future,
      );

      ref.invalidate(sellerInventoryExportProvider(_selectedSellerId!));
      final inventory = await ref.read(
        sellerInventoryExportProvider(_selectedSellerId!).future,
      );

      // Shops are already loaded for the admin UI â€” safe to read from cache.
      final allShops = ref.read(shopsProvider).value ?? <ShopModel>[];

      // Build per-customer summary.
      // allTxs is already filtered to this seller by sellerTransactionsExportProvider.
      final shopMap = <String, SellerReportShop>{};
      for (final tx in allTxs) {
        final cid = tx.shopId;
        if (cid.isEmpty) continue;
        final cname = tx.shopName.isNotEmpty
            ? tx.shopName
            : allShops.where((s) => s.id == cid).firstOrNull?.name ?? '';
        final existing = shopMap[cid];
        final pairsSold = tx.items.fold<int>(0, (acc, item) => acc + item.qty);
        final revenue = tx.isCashOut ? tx.amount : 0.0;
        shopMap[cid] = SellerReportShop(
          name: cname,
          totalPairsSold: (existing?.totalPairsSold ?? 0) + pairsSold,
          totalRevenue: (existing?.totalRevenue ?? 0) + revenue,
          outstandingBalance: 0,
        );
      }
      // Add outstanding balance from shops collection
      for (final entry in shopMap.entries) {
        final match = allShops.where((s) => s.id == entry.key);
        if (match.isNotEmpty) {
          shopMap[entry.key] = SellerReportShop(
            name: entry.value.name,
            totalPairsSold: entry.value.totalPairsSold,
            totalRevenue: entry.value.totalRevenue,
            outstandingBalance: match.first.balance,
          );
        }
      }

      final stockReceived = inventory.fold<int>(
        0,
        (s, i) => s + i.quantityAvailable,
      );
      final stockSold = allTxs
          .expand((t) => t.items)
          .fold<int>(0, (s, item) => s + item.qty);
      final stockRemaining = (stockReceived - stockSold).clamp(0, 999999);

      final settings = await ref.read(settingsProvider.future);
      final labels = applyArabicColumnNamesToLabels(
        _labels(ref),
        locale: locale,
        enabled: settings.showArabicColumnNamesInEnglishReports,
      );
      final sellerRouteCurrency = seller.assignedRouteIds.isNotEmpty
          ? ref.read(routeCurrencyProvider(seller.assignedRouteIds.first))
          : 'SAR';
      if (!context.mounted) return;
      ExportSheet.show(
        // ignore: use_build_context_synchronously
        context,
        ref,
        title: '${seller.displayName} - ${tr('seller_report', ref)}',
        headers: [
          tr('shop', ref),
          tr('stock_sold', ref),
          tr('revenue', ref),
          tr('outstanding', ref),
        ],
        rows: shopMap.values
            .map(
              (c) => [
                c.name,
                c.totalPairsSold,
                AppFormatters.currency(c.totalRevenue, sellerRouteCurrency),
                AppFormatters.currency(
                  c.outstandingBalance,
                  sellerRouteCurrency,
                ),
              ],
            )
            .toList(),
        fileName: AppFormatters.exportFileName(
          ExportNames.sellerReport,
          seller.displayName,
        ),
        pdfBytesBuilder: () {
          // Resolve route UID â†’ display name so PDF never shows raw IDs
          final routes = ref.read(routesProvider).value ?? <RouteModel>[];
          final routeMatch = routes.where(
            (r) => seller.assignedRouteIds.contains(r.id),
          );
          final routeDisplayName = routeMatch.isNotEmpty
              ? '${routeMatch.first.routeNumber} Â· ${routeMatch.first.name}'
              : '';
          return buildPdfSellerReport(
            sellerName: seller.displayName,
            sellerPhone: seller.phone ?? '',
            routeName: routeDisplayName,
            shops: shopMap.values.toList(),
            stockReceived: stockReceived,
            stockSold: stockSold,
            stockRemaining: stockRemaining,
            labels: labels,
            locale: locale,
            logoBytes: settings.logoBytes,
            companyName: settings.companyName,
          );
        },
      );
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authUserProvider);
    final user = authAsync.value;
    if (user == null || !user.isAdmin) return const SizedBox.shrink();

    final usersAsync = ref.watch(allUsersProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bar_chart,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('seller_report', ref),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            usersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () => ref.invalidate(allUsersProvider),
              ),
              data: (users) {
                final sellers = users.where((u) => u.isSeller).toList();
                return DropdownButtonFormField<String>(
                  initialValue: _selectedSellerId,
                  decoration: InputDecoration(
                    labelText: tr('select_seller', ref),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: sellers
                      .map(
                        (u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(u.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSellerId = v),
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedSellerId == null || _generating
                    ? null
                    : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                label: Text(tr('export', ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
