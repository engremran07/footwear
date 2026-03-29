import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../models/shop_model.dart';
import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shop_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/user_provider.dart';
import '../providers/seller_inventory_provider.dart';
import '../models/seller_inventory_model.dart';
import '../models/user_model.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/export_sheet.dart';
import 'package:printing/printing.dart';
import '../core/utils/pdf_export.dart';

class ShopDetailScreen extends ConsumerStatefulWidget {
  final String shopId;
  const ShopDetailScreen({super.key, required this.shopId});
  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen> {
  void _showEditTransactionDialog(TransactionModel tx) {
    final amountC = TextEditingController(text: tx.amount.toStringAsFixed(2));
    final descC = TextEditingController(text: tx.description ?? '');
    String txType = tx.type;
    String saleType = tx.saleType ?? 'cash';
    DateTime selectedDate = tx.createdAt.toDate();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
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
                      onSelected: (_) => setS(() => txType = 'cash_in'),
                      selectedColor:
                          AppTheme.clearBg(Theme.of(ctx).colorScheme),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('cash_out', ref)),
                      selected: txType == 'cash_out',
                      onSelected: (_) => setS(() => txType = 'cash_out'),
                      selectedColor: AppTheme.debtBg(Theme.of(ctx).colorScheme),
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
                      onSelected: (_) => setS(() => saleType = 'cash'),
                      selectedColor:
                          AppTheme.clearBg(Theme.of(ctx).colorScheme),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_credit', ref)),
                      selected: saleType == 'credit',
                      onSelected: (_) => setS(() => saleType = 'credit'),
                      selectedColor:
                          AppTheme.warningBg(Theme.of(ctx).colorScheme),
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
                  if (picked != null) setS(() => selectedDate = picked);
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
                            txId: tx.id,
                            customerId: tx.customerId ?? tx.shopId,
                            oldAmount: tx.amount,
                            oldType: tx.type,
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

  Future<void> _confirmDeleteTransaction(TransactionModel tx) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('delete', ref),
      message: tr('confirm_delete_transaction', ref),
    );
    if (confirmed != true) return;
    try {
      await ref.read(transactionNotifierProvider.notifier).deleteTransaction(
            txId: tx.id,
            customerId:
                tx.customerId ?? (tx.shopId.isNotEmpty ? tx.shopId : null),
            amount: tx.amount,
            type: tx.type,
          );
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(key, ref))));
      }
    }
  }

  void _showReturnDialog(ShopModel shop) {
    final user = ref.read(authUserProvider).valueOrNull;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReturnSheet(shop: shop, user: user),
    );
  }

  Map<String, String> _labels() => {
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
      };

  Future<void> _generatePdf(ShopModel shop, List<TransactionModel> txs) async {
    try {
      final locale = ref.read(appLocaleProvider);
      final settings = await ref.read(settingsProvider.future);
      final user = ref.read(authUserProvider).valueOrNull;
      final allUsers = ref.read(allUsersProvider).valueOrNull ?? [];
      final entryByMap = {for (final u in allUsers) u.id: u.displayName};
      if (user != null) entryByMap[user.id] = user.displayName;
      final sorted = [...txs]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final logoBytes = settings.logoBytes;
      final bytes = await buildPdfLedger(
        customerName: shop.name,
        companyName: settings.companyName,
        generatedBy: user?.displayName ?? '',
        openingBalance: 0,
        transactions: sorted,
        labels: _labels(),
        locale: locale,
        showEntryBy: true,
        entryByMap: entryByMap,
        currency: settings.currency,
        logoBytes: logoBytes,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'statement_${shop.name.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
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
                      selectedColor:
                          AppTheme.clearBg(Theme.of(ctx).colorScheme),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_credit', ref)),
                      selected: saleType == 'credit',
                      onSelected: (_) =>
                          setModalState(() => saleType = 'credit'),
                      selectedColor:
                          AppTheme.warningBg(Theme.of(ctx).colorScheme),
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
                    backgroundColor: type == 'cash_in'
                        ? AppBrand.successColor
                        : AppBrand.errorColor,
                    foregroundColor: AppBrand.onPrimary,
                  ),
                  onPressed: () async {
                    final amount = double.tryParse(amountC.text.trim());
                    if (amount == null || amount <= 0) return;
                    final shop =
                        ref.read(shopDetailProvider(widget.shopId)).valueOrNull;
                    if (shop == null) return;
                    final user = ref.read(authUserProvider).valueOrNull;
                    try {
                      await ref
                          .read(transactionNotifierProvider.notifier)
                          .create(
                            shopId: shop.id,
                            shopName: shop.name,
                            routeId: shop.routeId.isNotEmpty
                                ? shop.routeId
                                : (user?.assignedRouteId ?? ''),
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
    final shopAsync = ref.watch(shopDetailProvider(widget.shopId));
    final txAsync = ref.watch(shopTransactionsProvider(widget.shopId));
    final user = ref.watch(authUserProvider).valueOrNull;
    return shopAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('${tr('error', ref)}: $e'))),
      data: (shop) {
        if (shop == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('not_found', ref))),
          );
        }
        final isDebt = shop.balance > 0;
        final cs = Theme.of(context).colorScheme;
        final balanceColor =
            isDebt ? AppTheme.debtFg(cs) : AppTheme.clearFg(cs);
        final balanceBgColor =
            isDebt ? AppTheme.debtBg(cs) : AppTheme.clearBg(cs);
        final canManageShop = user?.isAdmin == true ||
            (user?.isSeller == true && user?.assignedRouteId == shop.routeId);

        return Scaffold(
          appBar: AppBar(
            title: Text(shop.name),
            actions: [
              if (canManageShop)
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => context.push('/shops/${shop.id}/edit'),
                ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: 'Export PDF',
                onPressed: () {
                  final txs = txAsync.valueOrNull ?? [];
                  _generatePdf(shop, txs);
                },
              ),
              IconButton(
                icon: const Icon(Icons.ios_share),
                onPressed: () {
                  final txs = txAsync.valueOrNull ?? [];
                  final sorted = [...txs]
                    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                  ExportSheet.show(
                    context,
                    ref,
                    title: '${shop.name} - ${tr('transactions', ref)}',
                    headers: [
                      tr('date', ref),
                      tr('type', ref),
                      tr('amount', ref),
                      tr('description', ref)
                    ],
                    rows: sorted
                        .map((t) => [
                              AppFormatters.dateTime(t.createdAt),
                              t.type == 'cash_in'
                                  ? tr('cash_in', ref)
                                  : tr('cash_out', ref),
                              AppFormatters.sar(t.amount),
                              t.description ?? '',
                            ])
                        .toList(),
                    fileName: 'shop_${shop.name}',
                    pdfBytesBuilder: () async {
                      final locale = ref.read(appLocaleProvider);
                      final settings = await ref.read(settingsProvider.future);
                      final user = ref.read(authUserProvider).valueOrNull;
                      final allUsers =
                          ref.read(allUsersProvider).valueOrNull ?? [];
                      final entryByMap = {
                        for (final u in allUsers) u.id: u.displayName
                      };
                      if (user != null) entryByMap[user.id] = user.displayName;
                      final logoBytes = settings.logoBytes;
                      return buildPdfLedger(
                        customerName: shop.name,
                        companyName: settings.companyName,
                        generatedBy: user?.displayName ?? '',
                        openingBalance: 0,
                        transactions: sorted,
                        labels: _labels(),
                        locale: locale,
                        showEntryBy: true,
                        entryByMap: entryByMap,
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
              // Shop info card
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
                            backgroundColor: balanceBgColor,
                            child: Text(
                              'R${shop.routeNumber}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: balanceColor),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(shop.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                if (shop.phone != null)
                                  Text(shop.phone!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                if (shop.area != null || shop.city != null)
                                  Text(
                                    [shop.area, shop.city]
                                        .where((e) => e != null)
                                        .join(', '),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Balance display
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: balanceBgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: balanceColor.withAlpha(80)),
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
                              AppFormatters.sar(shop.balance.abs()),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: balanceColor,
                                  ),
                            ),
                            Text(
                              shop.balance > 0
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
              // Quick cash buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppBrand.successColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: canManageShop
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
                        onPressed: canManageShop
                            ? () => _showQuickCash('cash_out')
                            : null,
                        icon: const Icon(Icons.remove),
                        label: Text(tr('cash_out', ref)),
                      ),
                    ),
                  ],
                ),
              ),
              // Return button (sellers only)
              if (canManageShop && user?.isSeller == true)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppBrand.warningColor,
                        side: const BorderSide(color: AppBrand.warningColor),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () => _showReturnDialog(shop),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Return'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Transactions header
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
              // Transaction list
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
                      itemBuilder: (_, i) => _TransactionTile(
                        tx: txs[i],
                        canEdit: user?.isAdmin == true ||
                            (user?.isSeller == true &&
                                user?.id == txs[i].createdBy),
                        onEdit: () => _showEditTransactionDialog(txs[i]),
                        onDelete: () => _confirmDeleteTransaction(txs[i]),
                      ),
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

class _TransactionTile extends ConsumerWidget {
  final TransactionModel tx;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _TransactionTile({
    required this.tx,
    this.canEdit = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCashIn = tx.type == 'cash_in';
    final color = isCashIn ? AppBrand.successColor : AppBrand.errorColor;
    final sign = isCashIn ? '+' : '-';
    final ppc = ref.watch(settingsProvider).valueOrNull?.pairsPerCarton ?? 12;
    final totalQty = tx.items.fold<int>(0, (acc, item) => acc + item.qty);

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withAlpha(25),
        child: Icon(
          isCashIn ? Icons.arrow_downward : Icons.arrow_upward,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        '$sign ${AppFormatters.sar(tx.amount)}',
        style:
            TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tx.description != null && tx.description!.isNotEmpty)
            Text(tx.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (tx.hasItems)
            Text(
              'Items: ${AppFormatters.stock(totalQty, ppc)}',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          Text(
            AppFormatters.dateTime(tx.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: canEdit
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) {
                if (v == 'edit' && onEdit != null) onEdit!();
                if (v == 'delete' && onDelete != null) onDelete!();
              },
              itemBuilder: (_) => [
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
                    const Icon(Icons.delete,
                        size: 16, color: AppBrand.errorColor),
                    const SizedBox(width: 8),
                    Text(tr('delete', ref),
                        style: const TextStyle(color: AppBrand.errorColor)),
                  ]),
                ),
              ],
            )
          : null,
      dense: true,
    );
  }
}

// ─── Return Sheet ─────────────────────────────────────────────────────────────

class _ReturnSheet extends ConsumerStatefulWidget {
  final ShopModel shop;
  final UserModel? user;

  const _ReturnSheet({required this.shop, this.user});

  @override
  ConsumerState<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends ConsumerState<_ReturnSheet> {
  final _amountC = TextEditingController();
  final _descC = TextEditingController();
  final Map<String, int> _selectedQtys = {};

  @override
  void dispose() {
    _amountC.dispose();
    _descC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showInventory = widget.user?.isSeller == true;
    final inventoryAsync = showInventory
        ? ref.watch(sellerInventoryProvider(widget.user!.id))
        : const AsyncData<List<SellerInventoryModel>>([]);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 24, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(tr('return', ref),
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountC,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('amount', ref),
                prefixIcon: const Icon(Icons.undo),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descC,
              decoration: InputDecoration(labelText: tr('description', ref)),
            ),
            if (showInventory) ...[
              const SizedBox(height: 16),
              Text(tr('return_items', ref),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              inventoryAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (items) {
                  if (items.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: items.map((item) {
                      final qty = _selectedQtys[item.id] ?? 0;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.variantName,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${tr("available", ref)}: ${item.quantityAvailable}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: qty <= 0
                                  ? null
                                  : () => setState(
                                      () => _selectedQtys[item.id] = qty - 1),
                            ),
                            SizedBox(
                              width: 30,
                              child: Text('$qty',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: qty >= item.quantityAvailable
                                  ? null
                                  : () => setState(
                                      () => _selectedQtys[item.id] = qty + 1),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppBrand.warningColor,
                  foregroundColor: AppBrand.onPrimary,
                ),
                onPressed: () async {
                  final amount = double.tryParse(_amountC.text.trim());
                  if (amount == null || amount <= 0) return;
                  final restores = Map<String, int>.fromEntries(
                    _selectedQtys.entries.where((e) => e.value > 0),
                  );
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref
                        .read(transactionNotifierProvider.notifier)
                        .createReturn(
                          shopId: widget.shop.id,
                          shopName: widget.shop.name,
                          routeId: widget.shop.routeId.isNotEmpty
                              ? widget.shop.routeId
                              : (widget.user?.assignedRouteId ?? ''),
                          amount: amount,
                          description: _descC.text.trim().isEmpty
                              ? null
                              : _descC.text.trim(),
                          sellerInventoryRestores: restores,
                          createdBy: widget.user?.id ?? '',
                        );
                    if (mounted) navigator.pop();
                  } catch (e) {
                    if (mounted) {
                      final key = AppErrorMapper.key(e);
                      messenger
                          .showSnackBar(SnackBar(content: Text(tr(key, ref))));
                    }
                  }
                },
                child: Text(tr('save', ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
