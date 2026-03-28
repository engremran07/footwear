import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../models/transaction_model.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_sheet.dart';
import '../core/utils/pdf_export.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});
  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  void _showEditTransactionDialog(Map<String, dynamic> tx) {
    final txId = tx['id'] as String;
    final oldAmount = (tx['amount'] as num).toDouble();
    final oldType = tx['type'] as String;
    final customerId = tx['customer_id'] as String?;
    final amountC = TextEditingController(text: oldAmount.toStringAsFixed(2));
    final descC =
        TextEditingController(text: (tx['description'] as String?) ?? '');
    String txType = oldType;
    String saleType = (tx['sale_type'] as String?) ?? 'cash';
    final createdAt = tx['created_at'] as Timestamp;
    DateTime selectedDate = createdAt.toDate();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 24, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('edit', ref), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('cash_in', ref)),
                      selected: txType == 'cash_in',
                      onSelected: (_) =>
                          setModalState(() => txType = 'cash_in'),
                      selectedColor: Colors.green.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('cash_out', ref)),
                      selected: txType == 'cash_out',
                      onSelected: (_) =>
                          setModalState(() => txType = 'cash_out'),
                      selectedColor: Colors.red.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountC,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('amount', ref),
                  prefixIcon: const Icon(Icons.attach_money),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descC,
                decoration: InputDecoration(
                  labelText: tr('description', ref),
                  prefixIcon: const Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_cash', ref)),
                      selected: saleType == 'cash',
                      onSelected: (_) => setModalState(() => saleType = 'cash'),
                      selectedColor: Colors.green.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_credit', ref)),
                      selected: saleType == 'credit',
                      onSelected: (_) =>
                          setModalState(() => saleType = 'credit'),
                      selectedColor: Colors.orange.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() => selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr('date', ref),
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(
                      '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final newAmount = double.tryParse(amountC.text.trim());
                    if (newAmount == null || newAmount <= 0) return;
                    try {
                      await ref
                          .read(transactionNotifierProvider.notifier)
                          .updateTransaction(
                            txId: txId,
                            customerId: customerId,
                            oldAmount: oldAmount,
                            oldType: oldType,
                            newAmount: newAmount,
                            newType: txType,
                            description: descC.text.trim().isEmpty
                                ? null
                                : descC.text.trim(),
                            saleType: saleType,
                            transactionDate: Timestamp.fromDate(selectedDate),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        final key = AppErrorMapper.key(e);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(tr(key, ref))));
                      }
                    }
                  },
                  child: Text(tr('save', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTransaction(Map<String, dynamic> tx) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('delete', ref),
      message: tr('confirm_delete_transaction', ref),
    );
    if (confirmed != true) return;
    try {
      await ref.read(transactionNotifierProvider.notifier).deleteTransaction(
            txId: tx['id'] as String,
            customerId: tx['customer_id'] as String?,
            amount: (tx['amount'] as num).toDouble(),
            type: tx['type'] as String,
          );
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(key, ref))));
      }
    }
  }

  void _showSellStockDialog() {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    final customer =
        ref.read(customerDetailProvider(widget.customerId)).valueOrNull;
    if (customer == null) return;
    final ppc = ref.read(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;
    const String saleType = 'cash';
    final DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return _SellStockSheet(
          user: user,
          customer: customer,
          ppc: ppc,
          saleType: saleType,
          selectedDate: selectedDate,
          onSell: (items, deductions, total, chosenSaleType, date) async {
            try {
              await ref
                  .read(transactionNotifierProvider.notifier)
                  .createSellerSale(
                    routeId: user.assignedRouteId ?? '',
                    customerId: customer.id,
                    customerName: customer.name,
                    amount: total,
                    saleType: chosenSaleType,
                    items: items,
                    sellerInventoryDeductions: deductions,
                    createdBy: user.id,
                    transactionDate: Timestamp.fromDate(date),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('success_created', ref))),
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                final key = AppErrorMapper.key(e);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(tr(key, ref))),
                );
              }
            }
          },
        );
      },
    );
  }

  void _showQuickCash(String type) {
    final amountC = TextEditingController();
    final descC = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String saleType = 'cash';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 24, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                type == 'cash_in' ? tr('cash_in', ref) : tr('cash_out', ref),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountC,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('amount', ref),
                  prefixIcon: const Icon(Icons.attach_money),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descC,
                decoration: InputDecoration(
                  labelText: tr('description', ref),
                  prefixIcon: const Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 12),
              // Sale type selector
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_cash', ref)),
                      selected: saleType == 'cash',
                      onSelected: (_) => setModalState(() => saleType = 'cash'),
                      selectedColor: Colors.green.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_credit', ref)),
                      selected: saleType == 'credit',
                      onSelected: (_) =>
                          setModalState(() => saleType = 'credit'),
                      selectedColor: Colors.orange.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() => selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr('date', ref),
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        type == 'cash_in' ? Colors.green : Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final amount = double.tryParse(amountC.text.trim());
                    if (amount == null || amount <= 0) return;
                    final customer = ref
                        .read(customerDetailProvider(widget.customerId))
                        .valueOrNull;
                    if (customer == null) return;
                    final user = ref.read(authUserProvider).valueOrNull;
                    try {
                      await ref
                          .read(transactionNotifierProvider.notifier)
                          .create(
                            shopId: '',
                            shopName: '',
                            routeId: '',
                            customerId: customer.id,
                            customerName: customer.name,
                            type: type,
                            saleType: saleType,
                            amount: amount,
                            description: descC.text.trim().isEmpty
                                ? null
                                : descC.text.trim(),
                            createdBy: user?.id ?? '',
                            transactionDate: Timestamp.fromDate(selectedDate),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: Text(tr('save', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(customerDetailProvider(widget.customerId));
    final txAsync = ref.watch(customerTransactionsProvider(widget.customerId));
    final user = ref.watch(authUserProvider).valueOrNull;
    final ppc = ref.watch(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;
    final isAdmin = user?.isAdmin == true;

    return customerAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('${tr('error', ref)}: $e'))),
      data: (customer) {
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('customer_not_found', ref))),
          );
        }
        final balanceColor =
            customer.balance > 0 ? Colors.red.shade700 : Colors.green.shade700;

        return Scaffold(
          appBar: AppBar(
            title: Text(customer.name),
            actions: [
              if (user != null)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () =>
                      context.push('/customers/${customer.id}/edit'),
                ),
              IconButton(
                icon: const Icon(Icons.ios_share),
                onPressed: () {
                  final txs = txAsync.valueOrNull ?? [];
                  final sorted = [...txs]..sort((a, b) {
                      final aTs = a['created_at'] as Timestamp;
                      final bTs = b['created_at'] as Timestamp;
                      return aTs.compareTo(bTs);
                    });
                  final txModels = sorted
                      .map((t) => TransactionModel.fromJson(
                          t as Map<String, dynamic>, t['id'] as String))
                      .toList();
                  ExportSheet.show(
                    context,
                    ref,
                    title: '${customer.name} - ${tr('transactions', ref)}',
                    headers: [
                      tr('date', ref),
                      tr('type', ref),
                      tr('amount', ref),
                      tr('description', ref)
                    ],
                    rows: sorted
                        .map((t) => [
                              AppFormatters.dateTime(
                                  t['created_at'] as Timestamp),
                              t['type'] == 'cash_in'
                                  ? tr('cash_in', ref)
                                  : tr('cash_out', ref),
                              AppFormatters.sar(
                                  (t['amount'] as num).toDouble()),
                              (t['description'] ?? '') as String,
                            ])
                        .toList(),
                    fileName: 'customer_${customer.name}',
                    pdfBytesBuilder: () async {
                      final locale = ref.read(appLocaleProvider);
                      final settings = await ref.read(settingsProvider.future);
                      final authUser = ref.read(authUserProvider).valueOrNull;
                      final allUsers =
                          ref.read(allUsersProvider).valueOrNull ?? [];
                      final entryByMap = {
                        for (final u in allUsers) u.id: u.displayName
                      };
                      if (authUser != null) {
                        entryByMap[authUser.id] = authUser.displayName;
                      }
                      final logoBytes = settings.logoBytes;
                      return buildPdfLedger(
                        customerName: customer.name,
                        companyName: settings.companyName,
                        generatedBy: authUser?.displayName ?? '',
                        openingBalance: 0,
                        transactions: txModels,
                        showEntryBy: true,
                        entryByMap: entryByMap,
                        labels: {
                          'date': tr('date', ref),
                          'description': tr('description', ref),
                          'debit': tr('debit', ref),
                          'credit': tr('credit', ref),
                          'running_balance': tr('running_balance', ref),
                          'account_statement': tr('account_statement', ref),
                          'net_payable': tr('net_payable', ref),
                          'page': tr('page', ref),
                          'report_date': tr('report_date', ref),
                          'cash_in': tr('cash_in', ref),
                          'cash_out': tr('cash_out', ref),
                          'total_entries': tr('total_entries', ref),
                          'generated_by': tr('generated_by', ref),
                          'duration': tr('duration', ref),
                          'entry_by': tr('entry_by', ref),
                          'mode': tr('mode', ref),
                        },
                        locale: locale,
                        currency: settings.currency,
                        logoBytes: logoBytes,
                      );
                    },
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Customer info card
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: balanceColor.withAlpha(30),
                            child: Text(
                              customer.name.isNotEmpty
                                  ? customer.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                  color: balanceColor),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(customer.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                if (customer.phone != null)
                                  Text(customer.phone!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                if (customer.city != null)
                                  Text(customer.city!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: balanceColor.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: balanceColor.withAlpha(40)),
                        ),
                        child: Column(
                          children: [
                            Text(tr('balance', ref),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: balanceColor)),
                            const SizedBox(height: 4),
                            Text(
                              AppFormatters.sar(customer.balance.abs()),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: balanceColor,
                                  ),
                            ),
                            Text(
                              customer.balance > 0
                                  ? tr('outstanding', ref)
                                  : tr('clear', ref),
                              style:
                                  TextStyle(color: balanceColor, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Quick cash buttons (admin) + Sell Stock button (seller)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppBrand.successColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: isAdmin
                                ? () => _showQuickCash('cash_in')
                                : null,
                            icon: const Icon(Icons.add),
                            label: Text(tr('cash_in', ref)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppBrand.errorColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: isAdmin
                                ? () => _showQuickCash('cash_out')
                                : null,
                            icon: const Icon(Icons.remove),
                            label: Text(tr('cash_out', ref)),
                          ),
                        ),
                      ],
                    ),
                    if (user?.isSeller == true) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _showSellStockDialog(),
                          icon: const Icon(Icons.sell),
                          label: Text(tr('sell_stock', ref)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(tr('transactions', ref),
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    txAsync.whenOrNull(
                          data: (txs) => Text('${txs.length}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ) ??
                        const SizedBox.shrink(),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: txAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (txs) {
                    if (txs.isEmpty) {
                      return EmptyState(
                        icon: Icons.receipt_long,
                        message: tr('no_transactions', ref),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: txs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final tx = txs[i];
                        final isCashIn = tx['type'] == 'cash_in';
                        final color =
                            isCashIn ? Colors.green : Colors.red.shade700;
                        final sign = isCashIn ? '+' : '-';
                        final amount = (tx['amount'] as num).toDouble();
                        final desc = tx['description'] as String?;
                        final createdAt = tx['created_at'] as Timestamp;
                        final rawItems =
                            tx['items'] as List<dynamic>? ?? const [];
                        final totalQty = rawItems.fold<int>(0, (acc, item) {
                          final m = item as Map<String, dynamic>?;
                          return acc + ((m?['qty'] as num?)?.toInt() ?? 0);
                        });
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: color.withAlpha(25),
                            child: Icon(
                              isCashIn
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: color,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            '$sign ${AppFormatters.sar(amount)}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color,
                                fontSize: 15),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (desc != null && desc.isNotEmpty)
                                Text(desc,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              if (totalQty > 0)
                                Text(
                                  'Items: ${AppFormatters.stock(totalQty, ppc)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              Text(
                                AppFormatters.dateTime(createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          trailing: () {
                            final canEdit = isAdmin ||
                                (user?.id == tx['created_by'] as String?);
                            if (!canEdit) return const SizedBox.shrink();
                            return PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _showEditTransactionDialog(
                                      tx as Map<String, dynamic>);
                                } else if (v == 'delete') {
                                  _confirmDeleteTransaction(
                                      tx as Map<String, dynamic>);
                                }
                              },
                              itemBuilder: (ctx) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(children: [
                                    const Icon(Icons.edit, size: 16),
                                    const SizedBox(width: 8),
                                    Text(tr('edit', ref)),
                                  ]),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [
                                    Icon(Icons.delete,
                                        size: 16, color: Colors.red.shade700),
                                    const SizedBox(width: 8),
                                    Text(tr('delete', ref),
                                        style: TextStyle(
                                            color: Colors.red.shade700)),
                                  ]),
                                ),
                              ],
                            );
                          }(),
                          dense: true,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Sell Stock Bottom Sheet ──────────────────────────────────────────────────

class _SellStockSheet extends ConsumerStatefulWidget {
  final dynamic user;
  final dynamic customer;
  final int ppc;
  final String saleType;
  final DateTime selectedDate;
  final Future<void> Function(
    List<TransactionItem> items,
    Map<String, int> deductions,
    double total,
    String saleType,
    DateTime date,
  ) onSell;

  const _SellStockSheet({
    required this.user,
    required this.customer,
    required this.ppc,
    required this.saleType,
    required this.selectedDate,
    required this.onSell,
  });

  @override
  ConsumerState<_SellStockSheet> createState() => _SellStockSheetState();
}

class _SellStockSheetState extends ConsumerState<_SellStockSheet> {
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, bool> _selected = {};
  String _saleType = 'cash';
  DateTime _date = DateTime.now();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _saleType = widget.saleType;
    _date = widget.selectedDate;
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _computeTotal(List<dynamic> items) {
    double total = 0;
    for (final item in items) {
      if (_selected[item.id] != true) continue;
      final qty = int.tryParse(_qtyControllers[item.id]?.text ?? '') ?? 0;
      final price =
          double.tryParse(_priceControllers[item.id]?.text ?? '') ?? 0;
      total += qty * price;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final sellerId = widget.user.id as String;
    final inventoryAsync = ref.watch(sellerInventoryProvider(sellerId));

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 24, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: inventoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (inventory) {
          if (inventory.isEmpty) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(tr('no_stock_available', ref),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('cancel', ref)),
                ),
              ],
            );
          }

          // Init controllers lazily
          for (final item in inventory) {
            _qtyControllers.putIfAbsent(item.id, () => TextEditingController());
            _priceControllers.putIfAbsent(
                item.id, () => TextEditingController());
            _selected.putIfAbsent(item.id, () => false);
          }

          return StatefulBuilder(
            builder: (ctx, setS) {
              final total = _computeTotal(inventory);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('sell_stock', ref),
                      style: Theme.of(ctx).textTheme.titleLarge),
                  Text(widget.customer.name as String,
                      style: Theme.of(ctx).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: inventory.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = inventory[i];
                        final isSelected = _selected[item.id] ?? false;
                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          onChanged: (v) =>
                              setS(() => _selected[item.id] = v ?? false),
                          title: Text(item.variantName,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${tr('available', ref)}: ${AppFormatters.stock(item.quantityAvailable, widget.ppc)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          secondary: isSelected
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      child: TextField(
                                        controller: _qtyControllers[item.id],
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Qty',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 4),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => setS(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    SizedBox(
                                      width: 72,
                                      child: TextField(
                                        controller: _priceControllers[item.id],
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'Price',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 4),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => setS(() {}),
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  // Sale type
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text(tr('sale_cash', ref)),
                          selected: _saleType == 'cash',
                          onSelected: (_) => setS(() => _saleType = 'cash'),
                          selectedColor: Colors.green.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: Text(tr('sale_credit', ref)),
                          selected: _saleType == 'credit',
                          onSelected: (_) => setS(() => _saleType = 'credit'),
                          selectedColor: Colors.orange.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Date picker
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setS(() => _date = picked);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: tr('date', ref),
                        prefixIcon: const Icon(Icons.calendar_today),
                        isDense: true,
                      ),
                      child: Text('${_date.day}/${_date.month}/${_date.year}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tr('total_amount', ref),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        AppFormatters.sar(total),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Theme.of(ctx).colorScheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _loading || total <= 0
                          ? null
                          : () async {
                              // Validate selections
                              final items = <TransactionItem>[];
                              final deductions = <String, int>{};
                              bool hasError = false;
                              for (final item in inventory) {
                                if (_selected[item.id] != true) continue;
                                final qty = int.tryParse(
                                        _qtyControllers[item.id]?.text ?? '') ??
                                    0;
                                final price = double.tryParse(
                                        _priceControllers[item.id]?.text ??
                                            '') ??
                                    0;
                                if (qty <= 0 || price <= 0) {
                                  hasError = true;
                                  break;
                                }
                                if (qty > item.quantityAvailable) {
                                  hasError = true;
                                  break;
                                }
                                items.add(TransactionItem(
                                  variantId: item.variantId,
                                  sku: item.variantName,
                                  productName: item.variantName,
                                  size: '',
                                  color: '',
                                  qty: qty,
                                  unitPrice: price,
                                  subtotal: qty * price,
                                ));
                                deductions[item.id] = qty;
                              }
                              if (hasError || items.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please check quantities and prices')),
                                );
                                return;
                              }
                              setS(() => _loading = true);
                              await widget.onSell(
                                  items, deductions, total, _saleType, _date);
                              if (mounted) setS(() => _loading = false);
                            },
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sell),
                      label: Text(tr('sell_stock', ref)),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
