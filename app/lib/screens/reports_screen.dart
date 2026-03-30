import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/formatters.dart';
import '../core/utils/pdf_export.dart';
import '../core/utils/snack_helper.dart';
import '../models/customer_model.dart';
import '../models/shop_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/product_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/export_sheet.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authUserProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final ppc = ref.watch(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;
    return Scaffold(
      appBar: AppBar(title: Text(tr('reports', ref))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary card
          stats.when(
            data: (s) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('summary', ref),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _Row(
                        label: tr('total_routes', ref),
                        value: '${s.totalRoutes}'),
                    _Row(
                        label: tr('total_shops', ref),
                        value: '${s.totalShops}'),
                    _Row(
                        label: tr('outstanding_balance', ref),
                        value: AppFormatters.sar(s.totalOutstanding)),
                    _Row(
                        label: tr('total_products', ref),
                        value: '${s.totalProducts}'),
                    _Row(
                        label: tr('total_variants', ref),
                        value: '${s.totalVariants}'),
                    _Row(
                        label: tr('stock_pairs', ref),
                        value: AppFormatters.stock(s.totalStockPairs, ppc)),
                  ],
                ),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
          ),
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
            icon: Icons.people,
            title: tr('customers_report', ref),
            onExport: () => _exportCustomers(context, ref),
          ),
          _ExportCard(
            icon: Icons.money_off,
            title: tr('bad_debts_report', ref),
            onExport: () => _exportBadDebts(context, ref),
          ),
          const _AccountStatementCard(),
          const _SellerReportCard(),
        ],
      ),
    );
  }

  void _exportShops(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).valueOrNull;
    final routeId = user?.assignedRouteId ?? '';
    final shops = user?.isAdmin == true
        ? ref.read(shopsProvider).valueOrNull ?? <ShopModel>[]
        : (routeId.isNotEmpty
            ? ref.read(shopsByRouteProvider(routeId)).valueOrNull ??
                <ShopModel>[]
            : <ShopModel>[]);
    ExportSheet.show(
      context,
      ref,
      title: tr('shops_report', ref),
      headers: [
        tr('name', ref),
        tr('route', ref),
        tr('phone', ref),
        tr('area', ref),
        tr('city', ref),
        tr('balance', ref),
      ],
      rows: shops
          .map((s) => [
                s.name,
                'R${s.routeNumber}',
                s.phone ?? '',
                s.area ?? '',
                s.city ?? '',
                AppFormatters.sar(s.balance),
              ])
          .toList(),
      fileName: 'shops_report',
    );
  }

  void _exportInventory(BuildContext context, WidgetRef ref, int ppc) {
    final variants = ref.read(allVariantsProvider).valueOrNull ?? [];
    ExportSheet.show(
      context,
      ref,
      title: tr('inventory_report', ref),
      headers: [
        tr('variant_name', ref),
        tr('stock_pairs', ref),
      ],
      rows: variants
          .map((v) => [
                v.variantName,
                AppFormatters.stock(v.quantityAvailable, ppc),
              ])
          .toList(),
      fileName: 'inventory_report',
    );
  }

  void _exportTransactions(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).valueOrNull;
    final txs = user?.isAdmin == true
        ? ref.read(allTransactionsProvider).valueOrNull ?? []
        : ref.read(sellerTransactionsProvider(user?.id ?? '')).valueOrNull ??
            [];
    ExportSheet.show(
      context,
      ref,
      title: tr('transactions_report', ref),
      headers: [
        tr('date', ref),
        tr('shop_name', ref),
        tr('type', ref),
        tr('amount', ref),
        tr('description', ref),
      ],
      rows: txs
          .map((t) => [
                AppFormatters.dateTime(t.createdAt),
                t.shopName,
                t.type == 'cash_in' ? tr('cash_in', ref) : tr('cash_out', ref),
                AppFormatters.sar(t.amount),
                t.description ?? '',
              ])
          .toList(),
      fileName: 'transactions_report',
    );
  }

  void _exportOutstanding(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).valueOrNull;
    final routeId = user?.assignedRouteId ?? '';
    final shops = user?.isAdmin == true
        ? ref.read(outstandingShopsProvider).valueOrNull ?? <ShopModel>[]
        : (routeId.isNotEmpty
            ? ref.read(outstandingShopsByRouteProvider(routeId)).valueOrNull ??
                <ShopModel>[]
            : <ShopModel>[]);
    ExportSheet.show(
      context,
      ref,
      title: tr('outstanding_report', ref),
      headers: [
        tr('name', ref),
        tr('route', ref),
        tr('phone', ref),
        tr('balance', ref),
      ],
      rows: shops
          .map((s) => [
                s.name,
                'R${s.routeNumber}',
                s.phone ?? '',
                AppFormatters.sar(s.balance),
              ])
          .toList(),
      fileName: 'outstanding_report',
    );
  }

  void _exportCustomers(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).valueOrNull;
    final routeId = user?.assignedRouteId ?? '';
    final customers = user?.isAdmin == true
        ? ref.read(customersProvider).valueOrNull ?? <CustomerModel>[]
        : (routeId.isNotEmpty
            ? ref.read(customersByRouteProvider(routeId)).valueOrNull ??
                <CustomerModel>[]
            : <CustomerModel>[]);
    ExportSheet.show(
      context,
      ref,
      title: tr('customers_report', ref),
      headers: [
        tr('name', ref),
        tr('phone', ref),
        tr('city', ref),
        tr('balance', ref),
      ],
      rows: customers
          .map((c) => [
                c.name,
                c.phone ?? '',
                c.city ?? '',
                AppFormatters.sar(c.balance),
              ])
          .toList(),
      fileName: 'customers_report',
    );
  }

  void _exportBadDebts(BuildContext context, WidgetRef ref) {
    final user = ref.read(authUserProvider).valueOrNull;
    final routeId = user?.assignedRouteId ?? '';
    final customers = user?.isAdmin == true
        ? ref.read(customersProvider).valueOrNull ?? <CustomerModel>[]
        : (routeId.isNotEmpty
            ? ref.read(customersByRouteProvider(routeId)).valueOrNull ??
                <CustomerModel>[]
            : <CustomerModel>[]);
    final badDebtCustomers = customers.where((c) => c.badDebt).toList();
    ExportSheet.show(
      context,
      ref,
      title: tr('bad_debts_report', ref),
      headers: [
        tr('name', ref),
        tr('phone', ref),
        tr('bad_debt_amount', ref),
        tr('date', ref),
      ],
      rows: badDebtCustomers
          .map((c) => [
                c.name,
                c.phone ?? '',
                AppFormatters.sar(c.badDebtAmount),
                c.badDebtDate != null
                    ? AppFormatters.dateTime(c.badDebtDate!)
                    : '',
              ])
          .toList(),
      fileName: 'bad_debts_report',
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
  const _ExportCard(
      {required this.icon, required this.title, required this.onExport});
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

// ─── Account Statement Card ────────────────────────────────────────────────
class _AccountStatementCard extends ConsumerStatefulWidget {
  const _AccountStatementCard();
  @override
  ConsumerState<_AccountStatementCard> createState() =>
      _AccountStatementCardState();
}

class _AccountStatementCardState extends ConsumerState<_AccountStatementCard> {
  String? _selectedCustomerId;
  bool _generating = false;

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
      'customer',
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
    if (_selectedCustomerId == null) return;
    setState(() => _generating = true);
    try {
      final locale = ref.read(appLocaleProvider);
      final user = ref.read(authUserProvider).valueOrNull;
      final routeId = user?.assignedRouteId ?? '';
      final customers = user?.isAdmin == true
          ? ref.read(customersProvider).valueOrNull ?? <CustomerModel>[]
          : (routeId.isNotEmpty
              ? ref.read(customersByRouteProvider(routeId)).valueOrNull ??
                  <CustomerModel>[]
              : <CustomerModel>[]);
      final customer = customers.firstWhere((c) => c.id == _selectedCustomerId);
      final allTxs = user?.isAdmin == true
          ? ref.read(allTransactionsProvider).valueOrNull ?? []
          : ref.read(sellerTransactionsProvider(user!.id)).valueOrNull ?? [];
      final txs = allTxs
          .where((t) =>
              t.customerId == _selectedCustomerId ||
              t.shopId == _selectedCustomerId)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final settings = await ref.read(settingsProvider.future);
      final allUsers = user?.isAdmin == true
          ? ref.read(allUsersProvider).valueOrNull ?? <UserModel>[]
          : <UserModel>[];
      final entryByMap = <String, String>{
        for (final u in allUsers) u.id: u.displayName
      };
      if (user != null) entryByMap[user.id] = user.displayName;

      final bytes = await buildPdfLedger(
        customerName: customer.name,
        companyName: settings.companyName,
        generatedBy: user?.displayName ?? '',
        openingBalance: 0,
        transactions: txs,
        entryByMap: entryByMap,
        showEntryBy: true,
        labels: _labels(ref),
        locale: locale,
        currency: settings.currency,
        logoBytes: settings.logoBytes,
      );
      if (!mounted) return;
      ExportSheet.show(
        context,
        ref,
        title: '${customer.name} - ${tr('account_statement', ref)}',
        headers: [
          tr('date', ref),
          tr('type', ref),
          tr('amount', ref),
          tr('description', ref),
        ],
        rows: txs
            .map((t) => [
                  AppFormatters.dateTime(t.createdAt),
                  t.type == 'cash_in'
                      ? tr('cash_in', ref)
                      : tr('cash_out', ref),
                  AppFormatters.sar(t.amount),
                  t.description ?? '',
                ])
            .toList(),
        fileName: 'account_statement_${customer.name.replaceAll(' ', '_')}',
        pdfBytesBuilder: () async => bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('$e'));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final routeId = user?.assignedRouteId ?? '';
    final AsyncValue<List<CustomerModel>> customersAsync = user?.isAdmin == true
        ? ref.watch(customersProvider)
        : (routeId.isNotEmpty
            ? ref.watch(customersByRouteProvider(routeId))
            : const AsyncData(<CustomerModel>[]));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(tr('account_statement', ref),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            customersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (customers) => DropdownButtonFormField<String>(
                initialValue: _selectedCustomerId,
                decoration: InputDecoration(
                  labelText: tr('customer', ref),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: customers
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCustomerId = v),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedCustomerId == null || _generating
                    ? null
                    : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
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

// ─── Seller Report Card (admin only) ─────────────────────────────────────────
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
      'customers',
      'customer',
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
      final users = ref.read(allUsersProvider).valueOrNull ?? [];
      final seller = users.firstWhere((u) => u.id == _selectedSellerId);
      final allTxs = ref.read(allTransactionsProvider).valueOrNull ?? [];
      final inventory =
          ref.read(sellerInventoryProvider(_selectedSellerId!)).valueOrNull ??
              [];
      final allCustomers = ref.read(customersProvider).valueOrNull ?? [];

      // Build per-customer summary
      final txsBySeller =
          allTxs.where((t) => t.createdBy == _selectedSellerId).toList();
      final customerMap = <String, SellerReportCustomer>{};
      for (final tx in txsBySeller) {
        final cid = tx.customerId ?? tx.shopId;
        if (cid.isEmpty) continue;
        final cname = tx.customerName ??
            allCustomers
                .firstWhere((c) => c.id == cid,
                    orElse: () => allCustomers.first)
                .name;
        final existing = customerMap[cid];
        final pairsSold = tx.items.fold<int>(0, (sum, item) => sum + item.qty);
        final revenue = tx.isCashOut ? tx.amount : 0.0;
        customerMap[cid] = SellerReportCustomer(
          name: cname,
          totalPairsSold: (existing?.totalPairsSold ?? 0) + pairsSold,
          totalRevenue: (existing?.totalRevenue ?? 0) + revenue,
          outstandingBalance: 0,
        );
      }
      // Add outstanding balance from customers collection
      for (final entry in customerMap.entries) {
        final match = allCustomers.where((c) => c.id == entry.key);
        if (match.isNotEmpty) {
          customerMap[entry.key] = SellerReportCustomer(
            name: entry.value.name,
            totalPairsSold: entry.value.totalPairsSold,
            totalRevenue: entry.value.totalRevenue,
            outstandingBalance: match.first.balance,
          );
        }
      }

      final stockReceived =
          inventory.fold<int>(0, (s, i) => s + i.quantityAvailable);
      final stockSold = txsBySeller
          .expand((t) => t.items)
          .fold<int>(0, (s, item) => s + item.qty);
      final stockRemaining = (stockReceived - stockSold).clamp(0, 999999);

      final settings = await ref.read(settingsProvider.future);
      final bytes = await buildPdfSellerReport(
        sellerName: seller.displayName,
        sellerPhone: seller.phone ?? '',
        routeName: seller.assignedRouteId ?? '',
        customers: customerMap.values.toList(),
        stockReceived: stockReceived,
        stockSold: stockSold,
        stockRemaining: stockRemaining,
        labels: _labels(ref),
        locale: locale,
        logoBytes: settings.logoBytes,
      );
      if (!mounted) return;
      ExportSheet.show(
        context,
        ref,
        title: '${seller.displayName} - ${tr('seller_report', ref)}',
        headers: [
          tr('customer', ref),
          tr('stock_sold', ref),
          tr('revenue', ref),
          tr('outstanding', ref),
        ],
        rows: customerMap.values
            .map((c) => [
                  c.name,
                  c.totalPairsSold,
                  AppFormatters.sar(c.totalRevenue),
                  AppFormatters.sar(c.outstandingBalance),
                ])
            .toList(),
        fileName: 'seller_report_${seller.displayName.replaceAll(' ', '_')}',
        pdfBytesBuilder: () async => bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('$e'));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authUserProvider);
    final user = authAsync.valueOrNull;
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
                Icon(Icons.bar_chart,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(tr('seller_report', ref),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 10),
            usersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
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
                      .map((u) => DropdownMenuItem(
                          value: u.id, child: Text(u.displayName)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSellerId = v),
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _selectedSellerId == null || _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
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
