import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pnl_provider.dart';
import '../providers/order_provider.dart';
import '../providers/approval_provider.dart';
import '../providers/settings_provider.dart';
import '../models/order_model.dart';
import '../models/cash_transaction_model.dart';
import '../models/customer_model.dart';
import '../widgets/stat_card.dart';
import '../core/utils/formatters.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _scrollController = ScrollController();
  final _salesKey = GlobalKey();
  final _collectionsKey = GlobalKey();
  final _cashOutKey = GlobalKey();
  final _creditKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todaysOrders = ref.watch(todaysOrdersProvider);
    final todaysCashIn = ref.watch(todaysCashInProvider);
    final todaysCashOut = ref.watch(todaysCashOutProvider);
    final activeOrders = ref.watch(activeOrdersCountProvider);
    final pendingApprovals = ref.watch(pendingApprovalsCountProvider);
    final pnl = ref.watch(currentPnlProvider);
    final topCustomers = ref.watch(topCreditCustomersProvider);
    final userNames = ref.watch(userNameMapProvider);
    final settings = ref.watch(settingsProvider);

    final currency = settings.valueOrNull?.currencyPrimary ?? 'SAR';
    final today = DateFormat('dd MMM yyyy').format(DateTime.now());

    // Aggregated today values
    final todaySalesTotal =
        todaysOrders.valueOrNull?.fold<double>(0, (sum, o) => sum + o.total) ??
            0;
    final todayCollectedTotal =
        todaysCashIn.valueOrNull?.fold<double>(0, (sum, t) => sum + t.amount) ??
            0;
    final todayCashOutTotal = todaysCashOut.valueOrNull
            ?.fold<double>(0, (sum, t) => sum + t.amount) ??
        0;
    final todayOrderCount = todaysOrders.valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text('${tr('dashboard', ref)} — $today')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todaysOrdersProvider);
          ref.invalidate(todaysCashInProvider);
          ref.invalidate(todaysCashOutProvider);
          ref.invalidate(topCreditCustomersProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── KPI Row ─────────────────────────────────────────────
            Text(tr('todays_snapshot', ref),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _KpiGrid(children: [
              StatCard(
                title: tr('todays_sales', ref),
                value: todaysOrders.isLoading
                    ? '...'
                    : AppFormatters.currency(todaySalesTotal, currency),
                subtitle: '$todayOrderCount ${tr('orders', ref).toLowerCase()}',
                icon: Icons.point_of_sale,
                color: AppBrand.successColor,
                staggerIndex: 0,
                onTap: () => _scrollTo(_salesKey),
              ),
              StatCard(
                title: tr('cash_collected', ref),
                value: todaysCashIn.isLoading
                    ? '...'
                    : AppFormatters.currency(todayCollectedTotal, currency),
                subtitle:
                    '${todaysCashIn.valueOrNull?.length ?? 0} ${tr('transactions', ref).toLowerCase()}',
                icon: Icons.account_balance_wallet,
                color: AppBrand.primaryColor,
                staggerIndex: 1,
                onTap: () => _scrollTo(_collectionsKey),
              ),
              StatCard(
                title: tr('cash_out', ref),
                value: todaysCashOut.isLoading
                    ? '...'
                    : AppFormatters.currency(todayCashOutTotal, currency),
                subtitle:
                    '${todaysCashOut.valueOrNull?.length ?? 0} ${tr('transactions', ref).toLowerCase()}',
                icon: Icons.money_off,
                color: AppBrand.warningColor,
                staggerIndex: 2,
                onTap: () => _scrollTo(_cashOutKey),
              ),
              StatCard(
                title: tr('active_orders', ref),
                value: activeOrders.when(
                  data: (c) => c.toString(),
                  loading: () => '...',
                  error: (_, __) => 'N/A',
                ),
                icon: Icons.shopping_cart,
                color: Colors.orange,
                staggerIndex: 3,
                onTap: () => context.go('/orders'),
              ),
              StatCard(
                title: tr('pending_approvals', ref),
                value: pendingApprovals.toString(),
                icon: Icons.approval,
                color: pendingApprovals > 0 ? AppBrand.errorColor : Colors.grey,
                staggerIndex: 4,
                onTap: () => context.go('/approvals'),
              ),
              StatCard(
                title: tr('mtd_revenue', ref),
                value: pnl.when(
                  data: (s) =>
                      AppFormatters.currency(s?.revenue ?? 0, currency),
                  loading: () => '...',
                  error: (_, __) => 'N/A',
                ),
                icon: Icons.trending_up,
                color: Colors.teal,
                staggerIndex: 5,
                onTap: () => context.go('/pnl'),
              ),
            ]),

            const SizedBox(height: 24),

            // ── Today's Sales by Seller ─────────────────────────────
            _SectionHeader(
              key: _salesKey,
              icon: Icons.storefront,
              title: tr('todays_sales_by_seller', ref),
              color: AppBrand.successColor,
            ),
            const SizedBox(height: 8),
            todaysOrders.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return _EmptyBanner(
                      message: tr('no_sales_today', ref),
                      icon: Icons.point_of_sale);
                }
                final nameMap = userNames.valueOrNull ?? {};
                return _SellerSalesBreakdown(
                  orders: orders,
                  nameMap: nameMap,
                  currency: currency,
                );
              },
              loading: () => const _LoadingTile(),
              error: (e, _) => _ErrorTile(message: '$e'),
            ),

            const SizedBox(height: 24),

            // ── Today's Collections by Seller ───────────────────────
            _SectionHeader(
              key: _collectionsKey,
              icon: Icons.account_balance_wallet,
              title: tr('todays_collections', ref),
              color: AppBrand.primaryColor,
            ),
            const SizedBox(height: 8),
            todaysCashIn.when(
              data: (txns) {
                if (txns.isEmpty) {
                  return _EmptyBanner(
                      message: tr('no_cash_today', ref), icon: Icons.money_off);
                }
                return _CashCollectionsList(
                    transactions: txns, currency: currency);
              },
              loading: () => const _LoadingTile(),
              error: (e, _) => _ErrorTile(message: '$e'),
            ),

            const SizedBox(height: 24),

            // ── Today's Cash Out by Seller ───────────────────────────
            _SectionHeader(
              key: _cashOutKey,
              icon: Icons.money_off,
              title: tr('todays_cash_out', ref),
              color: AppBrand.warningColor,
            ),
            const SizedBox(height: 8),
            todaysCashOut.when(
              data: (txns) {
                if (txns.isEmpty) {
                  return _EmptyBanner(
                      message: tr('no_cash_out_today', ref),
                      icon: Icons.money_off);
                }
                final nameMap = userNames.valueOrNull ?? {};
                return _CashOutBySellerBreakdown(
                    transactions: txns, nameMap: nameMap, currency: currency);
              },
              loading: () => const _LoadingTile(),
              error: (e, _) => _ErrorTile(message: '$e'),
            ),

            const SizedBox(height: 24),

            // ── Top Credit Customers ────────────────────────────────
            _SectionHeader(
              key: _creditKey,
              icon: Icons.credit_score,
              title: tr('highest_credit', ref),
              color: AppBrand.errorColor,
            ),
            const SizedBox(height: 8),
            topCustomers.when(
              data: (customers) {
                final withBalance =
                    customers.where((c) => c.balance > 0).toList();
                if (withBalance.isEmpty) {
                  return _EmptyBanner(
                      message: tr('no_credit', ref), icon: Icons.check_circle);
                }
                return _CreditLeaderboard(
                    customers: withBalance, currency: currency);
              },
              loading: () => const _LoadingTile(),
              error: (e, _) => _ErrorTile(message: '$e'),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── KPI Grid ────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  final List<Widget> children;
  const _KpiGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount = constraints.maxWidth >= 900
          ? 3
          : constraints.maxWidth >= 600
              ? 2
              : 1;
      return GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.7,
        children: children,
      );
    });
  }
}

// ─── Section Header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionHeader(
      {super.key,
      required this.icon,
      required this.title,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── Seller Sales Breakdown ──────────────────────────────────────────────────

class _SellerSalesBreakdown extends StatelessWidget {
  final List<OrderModel> orders;
  final Map<String, String> nameMap;
  final String currency;
  const _SellerSalesBreakdown(
      {required this.orders, required this.nameMap, required this.currency});

  @override
  Widget build(BuildContext context) {
    // Group orders by created_by UID
    final Map<String, List<OrderModel>> grouped = {};
    for (final order in orders) {
      grouped.putIfAbsent(order.createdBy, () => []).add(order);
    }

    // Sort sellers by total descending
    final sellers = grouped.entries.toList()
      ..sort((a, b) {
        final totalA = a.value.fold<double>(0, (s, o) => s + o.total);
        final totalB = b.value.fold<double>(0, (s, o) => s + o.total);
        return totalB.compareTo(totalA);
      });

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: sellers.map((entry) {
          final uid = entry.key;
          final sellerOrders = entry.value;
          final sellerName = nameMap[uid] ?? uid.substring(0, 8);
          final sellerTotal =
              sellerOrders.fold<double>(0, (s, o) => s + o.total);

          return ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppBrand.successColor.withValues(alpha: 0.15),
              child: const Icon(Icons.person,
                  color: AppBrand.successColor, size: 20),
            ),
            title: Text(sellerName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${sellerOrders.length} orders  •  ${AppFormatters.currency(sellerTotal, currency)}'),
            trailing: Text(
              AppFormatters.currency(sellerTotal, currency),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppBrand.successColor,
                  fontSize: 15),
            ),
            children: sellerOrders.map((order) {
              return ListTile(
                dense: true,
                leading: _StatusDot(status: order.status),
                title: Text(order.customerName),
                subtitle: Text(
                    '${order.status.toUpperCase()}  •  ${AppFormatters.dateTime(order.createdAt)}'),
                trailing: Text(AppFormatters.currency(order.total, currency),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => context.go('/orders/${order.id}'),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Cash Collections List ───────────────────────────────────────────────────

class _CashCollectionsList extends StatelessWidget {
  final List<CashTransactionModel> transactions;
  final String currency;
  const _CashCollectionsList(
      {required this.transactions, required this.currency});

  @override
  Widget build(BuildContext context) {
    final total = transactions.fold<double>(0, (s, t) => s + t.amount);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppBrand.primaryColor.withValues(alpha: 0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${transactions.length} collections',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  AppFormatters.currency(total, currency),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppBrand.primaryColor),
                ),
              ],
            ),
          ),
          ...transactions.map((tx) {
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: tx.status == 'approved'
                    ? AppBrand.successColor.withValues(alpha: 0.15)
                    : AppBrand.warningColor.withValues(alpha: 0.15),
                child: Icon(
                  tx.status == 'approved' ? Icons.check : Icons.schedule,
                  size: 16,
                  color: tx.status == 'approved'
                      ? AppBrand.successColor
                      : AppBrand.warningColor,
                ),
              ),
              title: Text(tx.reference.isNotEmpty ? tx.reference : 'Cash In',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(
                  '${tx.pnlCategory}  •  ${tx.status.toUpperCase()}  •  ${AppFormatters.dateTime(tx.createdAt)}'),
              trailing: Text(
                AppFormatters.currency(tx.amount, currency),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => context.go('/cash'),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Cash Out by Seller Breakdown ────────────────────────────────────────────

class _CashOutBySellerBreakdown extends StatelessWidget {
  final List<CashTransactionModel> transactions;
  final Map<String, String> nameMap;
  final String currency;
  const _CashOutBySellerBreakdown(
      {required this.transactions,
      required this.nameMap,
      required this.currency});

  @override
  Widget build(BuildContext context) {
    // Group by created_by (seller UID is the person who logged the cash out)
    final Map<String, List<CashTransactionModel>> grouped = {};
    for (final tx in transactions) {
      // cash_transactions don't have created_by by default, but we use
      // the reference/description to categorize. Group by pnlCategory as proxy.
      final key = tx.pnlCategory;
      grouped.putIfAbsent(key, () => []).add(tx);
    }

    final total = transactions.fold<double>(0, (s, t) => s + t.amount);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppBrand.warningColor.withValues(alpha: 0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${transactions.length} cash-out entries',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  AppFormatters.currency(total, currency),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppBrand.warningColor),
                ),
              ],
            ),
          ),
          ...grouped.entries.map((entry) {
            final catTotal =
                entry.value.fold<double>(0, (s, t) => s + t.amount);
            return ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: AppBrand.warningColor.withValues(alpha: 0.15),
                child: const Icon(Icons.category,
                    color: AppBrand.warningColor, size: 18),
              ),
              title: Text(entry.key.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${entry.value.length} entries'),
              trailing: Text(
                AppFormatters.currency(catTotal, currency),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppBrand.warningColor),
              ),
              children: entry.value.map((tx) {
                return ListTile(
                  dense: true,
                  title: Text(
                      tx.reference.isNotEmpty ? tx.reference : 'Cash Out',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                      '${tx.description ?? ''}  •  ${AppFormatters.dateTime(tx.createdAt)}'),
                  trailing: Text(
                    AppFormatters.currency(tx.amount, currency),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => context.go('/cash'),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Credit Leaderboard ──────────────────────────────────────────────────────

class _CreditLeaderboard extends StatelessWidget {
  final List<CustomerModel> customers;
  final String currency;
  const _CreditLeaderboard({required this.customers, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(customers.length, (i) {
          final c = customers[i];
          final rank = i + 1;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: rank <= 3
                  ? AppBrand.errorColor.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.12),
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: rank <= 3 ? AppBrand.errorColor : Colors.grey[700],
                ),
              ),
            ),
            title: Text(c.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle:
                Text('${c.totalOrders} orders  •  ${c.city ?? c.country}'),
            trailing: Text(
              AppFormatters.currency(c.balance, currency),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: rank <= 3 ? AppBrand.errorColor : Colors.grey[800],
                fontSize: 15,
              ),
            ),
            onTap: () => context.go('/customers/${c.id}'),
          );
        }),
      ),
    );
  }
}

// ─── Status Dot ──────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'delivered':
        color = AppBrand.successColor;
        break;
      case 'shipped':
        color = AppBrand.primaryColor;
        break;
      case 'processing':
        color = AppBrand.warningColor;
        break;
      case 'cancelled':
        color = AppBrand.errorColor;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

// ─── Shared helper widgets ───────────────────────────────────────────────────

class _EmptyBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyBanner({required this.message, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.grey[400], size: 28),
            const SizedBox(width: 12),
            Text(message,
                style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final String message;
  const _ErrorTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppBrand.errorColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppBrand.errorColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: const TextStyle(color: AppBrand.errorColor)),
            ),
          ],
        ),
      ),
    );
  }
}
