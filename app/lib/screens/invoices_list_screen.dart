import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_animations.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/invoice_model.dart';
import '../providers/auth_provider.dart';
import '../providers/invoice_provider.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';

class InvoicesListScreen extends ConsumerStatefulWidget {
  const InvoicesListScreen({super.key});
  @override
  ConsumerState<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends ConsumerState<InvoicesListScreen> {
  String _search = '';
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(roleAwareInvoicesProvider);
    final user = ref.watch(authUserProvider).value;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: (user != null && (user.isSeller || user.isAdmin))
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/invoices/new'),
              backgroundColor: AppBrand.primaryColor,
              foregroundColor: AppBrand.onPrimary,
              icon: const Icon(Icons.add),
              label: Text(tr('sale_invoice', ref)),
            )
          : null,
      body: Column(
        children: [
          AppSearchBar(
            hintText: tr('search', ref),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
          // Invoice summary strip
          invoicesAsync
                  .whenData((inv) => _InvoiceStatsStrip(invoices: inv))
                  .value ??
              const SizedBox.shrink(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', tr('all', ref), cs),
                  const SizedBox(width: 8),
                  _filterChip(InvoiceModel.statusIssued, tr('issued', ref), cs),
                  const SizedBox(width: 8),
                  _filterChip(InvoiceModel.statusPaid, tr('paid', ref), cs),
                  const SizedBox(width: 8),
                  _filterChip(
                    InvoiceModel.statusPartial,
                    tr('partial', ref),
                    cs,
                  ),
                  const SizedBox(width: 8),
                  _filterChip('void', tr('void', ref), cs),
                ],
              ),
            ),
          ),
          Expanded(
            child: invoicesAsync.when(
              data: (invoices) {
                var filtered = invoices;
                if (_statusFilter != 'all') {
                  filtered = filtered
                      .where((i) => i.status == _statusFilter)
                      .toList();
                }
                if (_search.isNotEmpty) {
                  filtered = filtered
                      .where(
                        (i) =>
                            i.invoiceNumber.toLowerCase().contains(_search) ||
                            i.shopName.toLowerCase().contains(_search) ||
                            i.sellerName.toLowerCase().contains(_search),
                      )
                      .toList();
                }
                if (filtered.isEmpty) {
                  return Center(child: Text(tr('no_data', ref)));
                }
                return AppPullRefresh(
                  onRefresh: () async {
                    ref.invalidate(roleAwareInvoicesProvider);
                    await Future.delayed(const Duration(milliseconds: 300));
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final inv = filtered[i];
                      return _InvoiceTile(invoice: inv).listEntry(i);
                    },
                  ),
                );
              },
              loading: () => const ShimmerLoading(),
              error: (e, _) => mappedErrorState(
                error: e,
                ref: ref,
                onRetry: () => ref.invalidate(roleAwareInvoicesProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, ColorScheme cs) {
    return ChoiceChip(
      label: Text(label),
      selected: _statusFilter == value,
      onSelected: (_) => setState(() => _statusFilter = value),
      selectedColor: AppTheme.clearBg(cs),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  final InvoiceModel invoice;
  const _InvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final date = invoice.createdAt.toDate();
    final dateStr = '${date.day}/${date.month}/${date.year}';

    Color statusColor;
    final statusLabel = switch (invoice.status) {
      InvoiceModel.statusPaid => tr('paid', ref),
      InvoiceModel.statusIssued => tr('issued', ref),
      InvoiceModel.statusPartial => tr('partial', ref),
      InvoiceModel.statusVoid => tr('void', ref),
      _ => invoice.status,
    };
    switch (invoice.status) {
      case InvoiceModel.statusPaid:
        statusColor = AppTheme.clearBg(cs);
        break;
      case InvoiceModel.statusIssued:
        statusColor = AppTheme.warningBg(cs);
        break;
      case 'void':
        statusColor = cs.errorContainer;
        break;
      default:
        statusColor = cs.surfaceContainerHighest;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/invoices/${invoice.id}'),
        leading: CircleAvatar(
          backgroundColor: invoice.isSale
              ? AppTheme.debtBg(cs)
              : AppTheme.clearBg(cs),
          child: Icon(
            invoice.isSale ? Icons.receipt : Icons.assignment_return,
            size: 20,
            color: invoice.isSale ? cs.error : cs.primary,
          ),
        ),
        title: Text(
          invoice.invoiceNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${invoice.shopName} • $dateStr',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AppFormatters.sar(invoice.total),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: invoice.isSale ? cs.error : cs.primary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel.toUpperCase(),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Invoice Stats Strip ───────────────────────────────────────────────────────

class _InvoiceStatsStrip extends ConsumerWidget {
  final List<InvoiceModel> invoices;
  const _InvoiceStatsStrip({required this.invoices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final sales = invoices.where((i) => i.isSale).toList();
    final totalSales = sales.fold(0.0, (sum, i) => sum + i.total);
    final paid = sales.where((i) => i.status == InvoiceModel.statusPaid);
    final paidAmount = paid.fold(0.0, (sum, i) => sum + i.total);
    final outstanding = totalSales - paidAmount;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _IStat(
            icon: Icons.receipt_long,
            label: tr('stats_total', ref),
            value: AppFormatters.sar(totalSales),
            color: cs.primary,
          ),
          Container(
            height: 28,
            width: 1,
            color: Theme.of(context).dividerColor,
          ),
          _IStat(
            icon: Icons.check_circle,
            label: tr('paid', ref),
            value: AppFormatters.sar(paidAmount),
            color: AppTheme.clearFg(cs),
          ),
          Container(
            height: 28,
            width: 1,
            color: Theme.of(context).dividerColor,
          ),
          _IStat(
            icon: Icons.pending,
            label: tr('pending', ref),
            value: AppFormatters.sar(outstanding),
            color: outstanding > 0 ? AppTheme.debtFg(cs) : AppTheme.clearFg(cs),
          ),
        ],
      ),
    );
  }
}

class _IStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _IStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: color,
        ),
      ),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
