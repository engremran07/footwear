import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack_helper.dart';
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

// =============================================================================
// ShopDetailScreen — live ledger view for a single retail shop.
//
// TWO FINANCIAL INTERACTION PATHWAYS:
//   1. CASH COLLECTION (existing debt only, no invoice):
//      └ Tap the quick cash_in button → _showQuickCash('cash_in')
//        → TransactionNotifier.create(type: 'cash_in')
//        → Reduces shop.balance atomically. No stock movement.
//
//   2. NEW SALE WITH STOCK → /invoices/new (CreateSaleInvoiceScreen):
//      └ Seller selects items from seller_inventory
//        → InvoiceNotifier.createSaleInvoice()
//        → Creates invoice + cash_out tx + stock deduction atomically.
//
// Additionally: return of goods uses _showReturnDialog → _ReturnSheet
//               → TransactionNotifier.createReturn()
//
// BAD DEBT: admin-only button in AppBar when balance > 0 && !shop.badDebt.
//           → ShopNotifier.markAsBadDebt() → zeros balance, flags shop.
// =============================================================================
class ShopDetailScreen extends ConsumerStatefulWidget {
  final String shopId;
  const ShopDetailScreen({super.key, required this.shopId});
  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen> {
  void _showEditTransactionDialog(TransactionModel tx) {
    final user = ref.read(authUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin == true;

    // Sellers can only annotate (description) — admins can change all fields.
    if (!isAdmin) {
      _showSellerAnnotateDialog(tx);
      return;
    }

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
            16,
            24,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
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
                      selectedColor: AppTheme.clearBg(
                        Theme.of(ctx).colorScheme,
                      ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: tr('amount', ref),
                  prefixIcon: const Icon(Icons.currency_exchange),
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
                      selectedColor: AppTheme.clearBg(
                        Theme.of(ctx).colorScheme,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_credit', ref)),
                      selected: saleType == 'credit',
                      onSelected: (_) => setS(() => saleType = 'credit'),
                      selectedColor: AppTheme.warningBg(
                        Theme.of(ctx).colorScheme,
                      ),
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
                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  ),
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
                        ScaffoldMessenger.of(
                          ctx,
                        ).showSnackBar(errorSnackBar(tr(key, ref)));
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

  /// Seller-only: annotate a transaction with a description correction.
  /// Financial fields (amount, type, date) are immutable for sellers.
  void _showSellerAnnotateDialog(TransactionModel tx) {
    final descC = TextEditingController(text: tx.description ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          24,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('edit', ref), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              tr('description', ref),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descC,
              decoration: InputDecoration(
                labelText: tr('description', ref),
                prefixIcon: const Icon(Icons.notes),
              ),
              maxLines: 3,
              autofocus: true,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(transactionNotifierProvider.notifier)
                        .updateTransactionNote(
                          txId: tx.id,
                          description: descC.text.trim().isEmpty
                              ? null
                              : descC.text.trim(),
                        );
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (ctx.mounted) {
                      final key = AppErrorMapper.key(e);
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(errorSnackBar(tr(key, ref)));
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

  Future<void> _confirmDeleteTransaction(TransactionModel tx) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('delete', ref),
      message: tr('confirm_delete_transaction', ref),
    );
    if (confirmed != true) return;
    try {
      final authUser = ref.read(authUserProvider).valueOrNull;
      await ref
          .read(transactionNotifierProvider.notifier)
          .deleteTransaction(
            txId: tx.id,
            customerId:
                tx.customerId ?? (tx.shopId.isNotEmpty ? tx.shopId : null),
            amount: tx.amount,
            type: tx.type,
            deletedBy: authUser?.id ?? '',
          );
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
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
    'opening_balance': tr('opening_balance', ref),
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
      final allUsers = user?.isAdmin == true
          ? ref.read(allUsersProvider).valueOrNull ?? <UserModel>[]
          : <UserModel>[];
      final entryByMap = <String, String>{
        for (final u in allUsers) u.id: u.displayName,
      };
      if (user != null) entryByMap[user.id] = user.displayName;
      final sorted = [...txs]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final logoBytes = settings.logoBytes;
      // Reconcile opening balance: stored balance minus the net of the
      // displayed transactions, so the final running balance equals shop.balance.
      final netTx = sorted.fold<double>(
        0.0,
        (s, t) => t.isCashOut ? s + t.amount : s - t.amount,
      );
      final bytes = await buildPdfLedger(
        customerName: shop.name,
        companyName: settings.companyName,
        generatedBy: user?.displayName ?? '',
        openingBalance: shop.balance - netTx,
        transactions: sorted,
        labels: _labels(),
        locale: locale,
        showEntryBy: true,
        entryByMap: entryByMap,
        dateFrom: sorted.isNotEmpty ? sorted.first.createdAt.toDate() : null,
        dateTo: sorted.isNotEmpty ? sorted.last.createdAt.toDate() : null,
        currency: settings.currency,
        logoBytes: logoBytes,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'statement_${shop.name.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('$e'));
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
            16,
            24,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: tr('amount', ref),
                  prefixIcon: const Icon(Icons.currency_exchange),
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
                      selectedColor: AppTheme.clearBg(
                        Theme.of(ctx).colorScheme,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(tr('sale_credit', ref)),
                      selected: saleType == 'credit',
                      onSelected: (_) =>
                          setModalState(() => saleType = 'credit'),
                      selectedColor: AppTheme.warningBg(
                        Theme.of(ctx).colorScheme,
                      ),
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
                    final shop = ref
                        .read(shopDetailProvider(widget.shopId))
                        .valueOrNull;
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
                        ScaffoldMessenger.of(
                          ctx,
                        ).showSnackBar(errorSnackBar('$e'));
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
        final balanceColor = isDebt
            ? AppTheme.debtFg(cs)
            : AppTheme.clearFg(cs);
        final balanceBgColor = isDebt
            ? AppTheme.debtBg(cs)
            : AppTheme.clearBg(cs);
        final canManageShop =
            user?.isAdmin == true ||
            (user?.isSeller == true && user?.assignedRouteId == shop.routeId);

        return Scaffold(
          appBar: AppBar(
            title: Text(shop.name),
            actions: [
              if (canManageShop)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: tr('tooltip_edit_shop', ref),
                  onPressed: () => context.push('/shops/${shop.id}/edit'),
                ),
              if (user?.isAdmin == true)
                IconButton(
                  icon: const Icon(Icons.delete, color: AppBrand.errorColor),
                  tooltip: tr('tooltip_delete_shop', ref),
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      context,
                      title: tr('delete', ref),
                      message: tr('confirm_delete_shop', ref),
                    );
                    if (ok != true) return;
                    try {
                      await ref
                          .read(shopNotifierProvider.notifier)
                          .deactivate(shop.id, shop.routeId);
                      if (context.mounted) context.go('/shops');
                    } catch (e) {
                      if (context.mounted) {
                        final key = AppErrorMapper.key(e);
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(errorSnackBar(tr(key, ref)));
                      }
                    }
                  },
                ),
              if (user?.isAdmin == true && shop.balance > 0 && !shop.badDebt)
                IconButton(
                  icon: const Icon(Icons.money_off, color: Colors.orange),
                  tooltip: tr('mark_bad_debt', ref),
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      context,
                      title: tr('bad_debt', ref),
                      message: tr('confirm_bad_debt', ref),
                    );
                    if (ok != true) return;
                    try {
                      await ref
                          .read(shopNotifierProvider.notifier)
                          .markAsBadDebt(shop.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        successSnackBar(tr('success_updated', ref)),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      final key = AppErrorMapper.key(e);
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(errorSnackBar(tr(key, ref)));
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                tooltip: tr('tooltip_export_pdf', ref),
                onPressed: () {
                  final txs = txAsync.valueOrNull ?? [];
                  _generatePdf(shop, txs);
                },
              ),
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: tr('tooltip_export_statement', ref),
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
                      tr('description', ref),
                    ],
                    rows: sorted
                        .map(
                          (t) => [
                            AppFormatters.dateTime(t.createdAt),
                            t.type == 'cash_in'
                                ? tr('cash_in', ref)
                                : tr('cash_out', ref),
                            AppFormatters.sar(t.amount),
                            t.description ?? '',
                          ],
                        )
                        .toList(),
                    fileName: 'shop_${shop.name}',
                    pdfBytesBuilder: () async {
                      final locale = ref.read(appLocaleProvider);
                      final settings = await ref.read(settingsProvider.future);
                      final user = ref.read(authUserProvider).valueOrNull;
                      final allUsers = user?.isAdmin == true
                          ? ref.read(allUsersProvider).valueOrNull ??
                                <UserModel>[]
                          : <UserModel>[];
                      final entryByMap = <String, String>{
                        for (final u in allUsers) u.id: u.displayName,
                      };
                      if (user != null) entryByMap[user.id] = user.displayName;
                      final logoBytes = settings.logoBytes;
                      // Reconcile opening balance
                      final netTx = sorted.fold<double>(
                        0.0,
                        (s, t) => t.isCashOut ? s + t.amount : s - t.amount,
                      );
                      return buildPdfLedger(
                        customerName: shop.name,
                        companyName: settings.companyName,
                        generatedBy: user?.displayName ?? '',
                        openingBalance: shop.balance - netTx,
                        transactions: sorted,
                        labels: _labels(),
                        locale: locale,
                        showEntryBy: true,
                        entryByMap: entryByMap,
                        dateFrom: sorted.isNotEmpty
                            ? sorted.first.createdAt.toDate()
                            : null,
                        dateTo: sorted.isNotEmpty
                            ? sorted.last.createdAt.toDate()
                            : null,
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
                                color: balanceColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shop.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                if (shop.phone != null)
                                  Text(
                                    shop.phone!,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (shop.area != null || shop.city != null)
                                  Text(
                                    [
                                      shop.area,
                                      shop.city,
                                    ].where((e) => e != null).join(', '),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
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
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: balanceBgColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: balanceColor.withAlpha(80)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              tr('balance', ref),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: balanceColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppFormatters.sar(shop.balance.abs()),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: balanceColor,
                                  ),
                            ),
                            Text(
                              shop.balance > 0
                                  ? tr('outstanding', ref)
                                  : tr('clear', ref),
                              style: TextStyle(
                                color: balanceColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Days overdue indicator
                      if (shop.balance > 0)
                        txAsync.whenOrNull(
                              data: (txs) {
                                if (txs.isEmpty) return const SizedBox.shrink();
                                final oldest = txs.last;
                                final days = DateTime.now()
                                    .difference(oldest.createdAt.toDate())
                                    .inDays;
                                final sev = days > 60
                                    ? AppBrand.errorColor
                                    : days > 30
                                    ? Colors.orange
                                    : cs.onSurfaceVariant;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        size: 14,
                                        color: sev,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$days ${tr('days_overdue', ref)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: sev,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ) ??
                            const SizedBox.shrink(),
                      // Balance trend mini chart
                      txAsync.whenOrNull(
                            data: (txs) {
                              if (txs.length < 2) {
                                return const SizedBox.shrink();
                              }
                              return _BalanceTrendChart(transactions: txs);
                            },
                          ) ??
                          const SizedBox.shrink(),
                      // Bad debt banner
                      if (shop.badDebt) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tr('bad_debt', ref),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    Text(
                                      '${tr('bad_debt_amount', ref)}: ${AppFormatters.sar(shop.badDebtAmount)}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
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
                      label: Text(tr('shop_return_btn', ref)),
                    ),
                  ),
                ),
              // Create Sale Invoice button (sellers only)
              if (canManageShop && user?.isSeller == true)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppBrand.primaryColor,
                        foregroundColor: AppBrand.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () =>
                          context.go('/invoices/new?shopId=${shop.id}'),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: Text(tr('create_sale_invoice', ref)),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              // Transactions header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      tr('transactions', ref),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    txAsync.whenOrNull(
                          data: (txs) => Text(
                            '${txs.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
                    // Build grouped items with month headers
                    final items = <_TxListItem>[];
                    String? lastMonth;
                    for (final tx in txs) {
                      final dt = tx.createdAt.toDate();
                      final monthKey =
                          '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
                      if (monthKey != lastMonth) {
                        items.add(
                          _TxListItem(
                            monthHeader: AppFormatters.period(monthKey),
                          ),
                        );
                        lastMonth = monthKey;
                      }
                      items.add(_TxListItem(tx: tx));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        if (item.monthHeader != null) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: Text(
                              item.monthHeader!,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        final tx = item.tx!;
                        return _TransactionTile(
                          tx: tx,
                          canEdit:
                              user?.isAdmin == true ||
                              (user?.isSeller == true &&
                                  user?.id == tx.createdBy),
                          canDelete: user?.isAdmin == true,
                          onEdit: () => _showEditTransactionDialog(tx),
                          onDelete: () => _confirmDeleteTransaction(tx),
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

class _TransactionTile extends ConsumerWidget {
  final TransactionModel tx;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _TransactionTile({
    required this.tx,
    this.canEdit = false,
    this.canDelete = false,
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
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 15,
        ),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 16),
                      const SizedBox(width: 8),
                      Text(tr('edit', ref)),
                    ],
                  ),
                ),
                if (canDelete)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.delete,
                          size: 16,
                          color: AppBrand.errorColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tr('delete', ref),
                          style: const TextStyle(color: AppBrand.errorColor),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          : null,
      dense: true,
    );
  }
}

// ─── Tx List Item ────────────────────────────────────────────────────────────

class _TxListItem {
  final String? monthHeader;
  final TransactionModel? tx;
  const _TxListItem({this.monthHeader, this.tx});
}

// ─── Balance Trend Mini Chart ─────────────────────────────────────────────────

class _BalanceTrendChart extends StatelessWidget {
  final List<TransactionModel> transactions;
  const _BalanceTrendChart({required this.transactions});

  String _shortMonth(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return m >= 1 && m <= 12 ? names[m - 1] : '';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...transactions]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (sorted.length < 2) return const SizedBox.shrink();

    // Aggregate monthly balances
    final monthlyBalance = <String, double>{};
    double running = 0;
    for (final tx in sorted) {
      running += tx.isCashOut ? tx.amount : -tx.amount;
      final dt = tx.createdAt.toDate();
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      monthlyBalance[key] = running;
    }

    final entries = monthlyBalance.entries.toList();
    final display = entries.length > 6
        ? entries.sublist(entries.length - 6)
        : entries;

    if (display.length < 2) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final spots = <FlSpot>[];
    for (var i = 0; i < display.length; i++) {
      spots.add(FlSpot(i.toDouble(), display[i].value));
    }

    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance Trend',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 80,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= display.length) {
                          return const SizedBox.shrink();
                        }
                        final parts = display[idx].key.split('-');
                        return Text(
                          _shortMonth(int.tryParse(parts[1]) ?? 1),
                          style: TextStyle(
                            fontSize: 9,
                            color: cs.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (display.length - 1).toDouble(),
                minY: minY < 0 ? minY : 0,
                maxY: maxY > 0 ? maxY * 1.1 : 100,
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: cs.primary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: cs.primary.withAlpha(30),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
        16,
        24,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                tr('return', ref),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountC,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
              Text(
                tr('return_items', ref),
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
                        title: Text(
                          item.variantName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${tr("available", ref)}: ${item.quantityAvailable}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18),
                              tooltip: 'Decrease quantity',
                              onPressed: qty <= 0
                                  ? null
                                  : () => setState(
                                      () => _selectedQtys[item.id] = qty - 1,
                                    ),
                            ),
                            SizedBox(
                              width: 30,
                              child: Text(
                                '$qty',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              tooltip: 'Increase quantity',
                              onPressed: qty >= item.quantityAvailable
                                  ? null
                                  : () => setState(
                                      () => _selectedQtys[item.id] = qty + 1,
                                    ),
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
                      messenger.showSnackBar(errorSnackBar(tr(key, ref)));
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
