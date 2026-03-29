import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/invoice_model.dart';
import '../providers/auth_provider.dart';
import '../providers/invoice_provider.dart';

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
    final user = ref.watch(authUserProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('invoices', ref)),
      ),
      floatingActionButton: (user != null && (user.isSeller || user.isAdmin))
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/invoices/new'),
              backgroundColor: AppBrand.primaryColor,
              foregroundColor: AppBrand.onPrimary,
              icon: const Icon(Icons.add),
              label: Text(tr('sale_invoice', ref)),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: tr('search', ref),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) =>
                  setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
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
                      InvoiceModel.statusPartial, tr('partial', ref), cs),
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
                  filtered =
                      filtered.where((i) => i.status == _statusFilter).toList();
                }
                if (_search.isNotEmpty) {
                  filtered = filtered
                      .where((i) =>
                          i.invoiceNumber.toLowerCase().contains(_search) ||
                          i.customerName.toLowerCase().contains(_search) ||
                          i.shopName.toLowerCase().contains(_search))
                      .toList();
                }
                if (filtered.isEmpty) {
                  return Center(child: Text(tr('no_data', ref)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final inv = filtered[i];
                    return _InvoiceTile(invoice: inv);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
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
        onTap: () => context.go('/invoices/${invoice.id}'),
        leading: CircleAvatar(
          backgroundColor:
              invoice.isSale ? AppTheme.debtBg(cs) : AppTheme.clearBg(cs),
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
          '${invoice.customerName} • $dateStr',
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
                invoice.status.toUpperCase(),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
