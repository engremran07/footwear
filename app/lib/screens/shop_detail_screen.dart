import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_brand.dart';
import '../core/design/app_animations.dart';
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

import '../models/user_model.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
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

enum _ShopAction { edit, delete, badDebt, pdf, share }

class ShopDetailScreen extends ConsumerStatefulWidget {
  final String shopId;
  const ShopDetailScreen({super.key, required this.shopId});
  @override
  ConsumerState<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends ConsumerState<ShopDetailScreen> {
  void _showEditTransactionDialog(TransactionModel tx) {
    final user = ref.read(authUserProvider).value;
    final isAdmin = user?.isAdmin == true;

    // Sellers can edit cash_in/cash_out; update may require admin approval
    // depending on settings toggle.
    if (!isAdmin) {
      _showSellerEditTransactionDialog(tx);
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
                            shopId: tx.shopId,
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

  /// Seller edit flow for cash_in/cash_out transactions.
  /// If admin approval is enabled, this submits a pending request.
  void _showSellerEditTransactionDialog(TransactionModel tx) {
    if (tx.type != 'cash_in' && tx.type != 'cash_out') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('seller_edit_cash_only', ref)));
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
                      final user = ref.read(authUserProvider).value;
                      final appliedImmediately = await ref
                          .read(transactionNotifierProvider.notifier)
                          .sellerEditTransaction(
                            txId: tx.id,
                            sellerId: user?.id ?? '',
                            newAmount: newAmount,
                            newType: txType,
                            description: descC.text.trim().isEmpty
                                ? null
                                : descC.text.trim(),
                            saleType: saleType,
                            transactionDate: Timestamp.fromDate(selectedDate),
                          );
                      if (!mounted) return;
                      if (ctx.mounted) Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        successSnackBar(
                          appliedImmediately
                              ? tr('saved_successfully', ref)
                              : tr('edit_request_submitted', ref),
                        ),
                      );
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

  Future<void> _reviewEditRequest(TransactionModel tx, bool approved) async {
    try {
      final user = ref.read(authUserProvider).value;
      await ref
          .read(transactionNotifierProvider.notifier)
          .reviewSellerEditRequest(
            txId: tx.id,
            approved: approved,
            reviewerId: user?.id ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        successSnackBar(
          approved
              ? tr('edit_request_approved', ref)
              : tr('edit_request_rejected', ref),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final key = AppErrorMapper.key(e);
      ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
    }
  }

  Future<void> _confirmDeleteTransaction(TransactionModel tx) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: tr('delete', ref),
      message: tr('confirm_delete_transaction', ref),
    );
    if (confirmed != true) return;
    try {
      final authUser = ref.read(authUserProvider).value;
      await ref
          .read(transactionNotifierProvider.notifier)
          .deleteTransaction(
            txId: tx.id,
            shopId: tx.shopId.isNotEmpty ? tx.shopId : null,
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

  String _transactionTypeLabel(TransactionModel tx) {
    return switch (tx.type) {
      TransactionModel.typeCashIn => tr('cash_in', ref),
      TransactionModel.typeCashOut => tr('cash_out', ref),
      TransactionModel.typeReturn => tr('return', ref),
      'write_off' => tr('write_off', ref),
      _ => tx.type.replaceAll('_', ' '),
    };
  }

  Future<List<TransactionModel>> _loadFullTransactions() async {
    final txs = await ref.read(
      shopTransactionsExportProvider(widget.shopId).future,
    );
    return [...txs]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> _generatePdf(ShopModel shop) async {
    try {
      final locale = ref.read(appLocaleProvider);
      final settings = await ref.read(settingsProvider.future);
      final user = ref.read(authUserProvider).value;
      final sorted = await _loadFullTransactions();
      final allUsers = user?.isAdmin == true
          ? await ref.read(allUsersProvider.future)
          : <UserModel>[];
      final entryByMap = <String, String>{
        for (final u in allUsers) u.id: u.displayName,
      };
      if (user != null) entryByMap[user.id] = user.displayName;
      final logoBytes = settings.logoBytes;
      // Reconcile opening balance: stored balance minus the net of the
      // displayed transactions, so the final running balance equals shop.balance.
      final netTx = sorted.fold<double>(0.0, (s, t) => s + t.balanceImpact);
      final bytes = await buildPdfLedger(
        shopName: shop.name,
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
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
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
                        .value;
                    if (shop == null) return;
                    final user = ref.read(authUserProvider).value;
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

  @override
  Widget build(BuildContext context) {
    final shopAsync = ref.watch(shopDetailProvider(widget.shopId));
    final txAsync = ref.watch(shopTransactionsProvider(widget.shopId));
    final user = ref.watch(authUserProvider).value;
    return shopAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: mappedErrorState(
          error: e,
          ref: ref,
          onRetry: () => ref.invalidate(shopDetailProvider(widget.shopId)),
        ),
      ),
      data: (shop) {
        if (shop == null) {
          return Scaffold(body: Center(child: Text(tr('not_found', ref))));
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
          body: Column(
            children: [
              // Actions menu — shop name is shown in AppBar breadcrumb
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Row(
                  children: [
                    const Spacer(),
                    PopupMenuButton<_ShopAction>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) async {
                        switch (action) {
                          case _ShopAction.edit:
                            context.push('/shops/${shop.id}/edit');

                          case _ShopAction.delete:
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

                          case _ShopAction.badDebt:
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

                          case _ShopAction.pdf:
                            _generatePdf(shop);

                          case _ShopAction.share:
                            final sorted = await _loadFullTransactions();
                            if (!context.mounted) return;
                            ExportSheet.show(
                              context,
                              ref,
                              title:
                                  '${shop.name} - ${tr('transactions', ref)}',
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
                                      _transactionTypeLabel(t),
                                      AppFormatters.sar(t.amount),
                                      t.description ?? '',
                                    ],
                                  )
                                  .toList(),
                              fileName: 'shop_${shop.name}',
                              pdfBytesBuilder: () async {
                                final locale = ref.read(appLocaleProvider);
                                final settings = await ref.read(
                                  settingsProvider.future,
                                );
                                final user = ref.read(authUserProvider).value;
                                final allUsers = user?.isAdmin == true
                                    ? await ref.read(allUsersProvider.future)
                                    : <UserModel>[];
                                final entryByMap = <String, String>{
                                  for (final u in allUsers) u.id: u.displayName,
                                };
                                if (user != null) {
                                  entryByMap[user.id] = user.displayName;
                                }
                                final logoBytes = settings.logoBytes;
                                final netTx = sorted.fold<double>(
                                  0.0,
                                  (s, t) => s + t.balanceImpact,
                                );
                                return buildPdfLedger(
                                  shopName: shop.name,
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
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (canManageShop)
                          PopupMenuItem(
                            value: _ShopAction.edit,
                            child: ListTile(
                              leading: const Icon(Icons.edit),
                              title: Text(tr('tooltip_edit_shop', ref)),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        if (user?.isAdmin == true)
                          PopupMenuItem(
                            value: _ShopAction.delete,
                            child: ListTile(
                              leading: const Icon(
                                Icons.delete,
                                color: AppBrand.errorColor,
                              ),
                              title: Text(
                                tr('tooltip_delete_shop', ref),
                                style: const TextStyle(
                                  color: AppBrand.errorColor,
                                ),
                              ),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        if (user?.isAdmin == true &&
                            shop.balance > 0 &&
                            !shop.badDebt)
                          PopupMenuItem(
                            value: _ShopAction.badDebt,
                            child: ListTile(
                              leading: const Icon(
                                Icons.money_off,
                                color: AppBrand.warningColor,
                              ),
                              title: Text(tr('mark_bad_debt', ref)),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        PopupMenuItem(
                          value: _ShopAction.pdf,
                          child: ListTile(
                            leading: const Icon(Icons.picture_as_pdf),
                            title: Text(tr('tooltip_export_pdf', ref)),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        PopupMenuItem(
                          value: _ShopAction.share,
                          child: ListTile(
                            leading: const Icon(Icons.ios_share),
                            title: Text(tr('tooltip_export_statement', ref)),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Shop info card
              Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Contact bar
                      Row(
                        children: [
                          if (shop.phone != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.phone_outlined,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              shop.phone!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (shop.area != null || shop.city != null) ...[
                            const Spacer(),
                            Text(
                              [
                                shop.area,
                                shop.city,
                              ].whereType<String>().join(', '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Total In / Total Out compact summary row
                      Row(
                        children: [
                          // Total In — cash collected from this shop
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.clearBg(cs),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppTheme.clearFg(cs).withAlpha(60),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    tr('total_in', ref),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: AppTheme.clearFg(cs)),
                                  ),
                                  const SizedBox(height: 2),
                                  txAsync.whenOrNull(
                                        data: (txs) {
                                          final totalIn = txs
                                              .where(
                                                (t) =>
                                                    !t.deleted && !t.isCashOut,
                                              )
                                              .fold(
                                                0.0,
                                                (s, t) => s + t.amount,
                                              );
                                          return Text(
                                            AppFormatters.sar(totalIn),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.clearFg(cs),
                                                ),
                                          );
                                        },
                                      ) ??
                                      Text(
                                        '—',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Total Out — current outstanding balance
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: balanceBgColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: balanceColor.withAlpha(60),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    tr('total_out', ref),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: balanceColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppFormatters.sar(shop.balance.abs()),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: balanceColor,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Days overdue indicator
                      if (shop.balance > 0)
                        txAsync.whenOrNull(
                              data: (txs) {
                                final activeTxs = txs
                                    .where((t) => !t.deleted)
                                    .toList();
                                if (activeTxs.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                final oldest = activeTxs.last;
                                final days = DateTime.now()
                                    .difference(oldest.createdAt.toDate())
                                    .inDays;
                                final sev = days > 60
                                    ? AppBrand.errorColor
                                    : days > 30
                                    ? AppBrand.warningColor
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
                              final activeTxs = txs
                                  .where((t) => !t.deleted)
                                  .toList();
                              if (activeTxs.length < 2) {
                                return const SizedBox.shrink();
                              }
                              return _BalanceTrendChart(
                                transactions: activeTxs,
                              );
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
                            color: AppBrand.warningColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppBrand.warningColor.withAlpha(120),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                color: AppBrand.warningColor,
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
                                        color: AppBrand.warningColor,
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
                          foregroundColor: AppBrand.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 10),
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
                          foregroundColor: AppBrand.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 10),
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
                            '${tr('showing_entries', ref)} ${txs.length}',
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
                  error: (e, _) => mappedErrorState(
                    error: e,
                    ref: ref,
                    onRetry: () =>
                        ref.invalidate(shopTransactionsProvider(widget.shopId)),
                  ),
                  data: (txs) {
                    if (txs.isEmpty) {
                      return EmptyState(
                        icon: Icons.receipt_long,
                        message: tr('no_transactions', ref),
                      );
                    }
                    final activeTxs = txs.where((t) => !t.deleted).toList();
                    // Compute running balance per transaction.
                    // Active txs are newest-first from the provider.
                    // Work backward from shop.balance to reconstruct each tx's
                    // post-transaction balance.
                    final balanceMap = <String, double>{};
                    double bal = shop.balance;
                    for (final tx in activeTxs) {
                      balanceMap[tx.id] = bal;
                      // Reverse the tx to get balance before it was applied
                      bal -= tx.balanceImpact;
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
                      items.add(
                        _TxListItem(tx: tx, runningBalance: balanceMap[tx.id]),
                      );
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
                          runningBalance: item.runningBalance,
                          canEdit:
                              !tx.deleted &&
                              !tx.editRequestPending &&
                              (user?.isAdmin == true ||
                                  (user?.isSeller == true &&
                                      user?.id == tx.createdBy &&
                                      (tx.invoiceId == null ||
                                          tx.invoiceId!.isEmpty) &&
                                      (tx.type == TransactionModel.typeCashIn ||
                                          tx.type ==
                                              TransactionModel.typeCashOut))),
                          canApproveEdit:
                              !tx.deleted &&
                              user?.isAdmin == true &&
                              tx.editRequestPending,
                          canDelete: !tx.deleted && user?.isAdmin == true,
                          onEdit: () => _showEditTransactionDialog(tx),
                          onApproveEdit: () => _reviewEditRequest(tx, true),
                          onRejectEdit: () => _reviewEditRequest(tx, false),
                          onDelete: () => _confirmDeleteTransaction(tx),
                        ).listEntry(i);
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
  final double? runningBalance;
  final bool canEdit;
  final bool canApproveEdit;
  final bool canDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onApproveEdit;
  final VoidCallback? onRejectEdit;
  final VoidCallback? onDelete;

  const _TransactionTile({
    required this.tx,
    this.runningBalance,
    this.canEdit = false,
    this.canApproveEdit = false,
    this.canDelete = false,
    this.onEdit,
    this.onApproveEdit,
    this.onRejectEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDeleted = tx.deleted;
    final isWriteOff = tx.isWriteOff;
    final reducesBalance = tx.reducesBalance;
    final color = isDeleted
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isWriteOff
        ? AppBrand.warningColor
        : (reducesBalance ? AppBrand.successColor : AppBrand.errorColor);
    final sign = reducesBalance ? '+' : '-';
    final ppc = ref.watch(settingsProvider).value?.pairsPerCarton ?? 12;
    final totalQty = tx.items.fold<int>(0, (acc, item) => acc + item.qty);

    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withAlpha(25),
        child: Icon(
          isDeleted
              ? Icons.remove_circle_outline
              : tx.isReturn
              ? Icons.assignment_return
              : isWriteOff
              ? Icons.money_off
              : (reducesBalance ? Icons.arrow_downward : Icons.arrow_upward),
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
          if (isDeleted)
            Text(
              tr('void', ref).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (tx.editRequestPending)
            Text(
              tr('pending_admin_approval', ref).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
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
          // Running balance (CreditBook-style)
          if (runningBalance != null)
            Text(
              '${tr('running_balance', ref)}: ${AppFormatters.sar(runningBalance!)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: runningBalance! > 0
                    ? AppBrand.errorColor
                    : runningBalance! < 0
                    ? AppBrand.successColor
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: (canEdit || canApproveEdit)
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) {
                if (v == 'edit' && onEdit != null) onEdit!();
                if (v == 'approve_edit' && onApproveEdit != null) {
                  onApproveEdit!();
                }
                if (v == 'reject_edit' && onRejectEdit != null) {
                  onRejectEdit!();
                }
                if (v == 'delete' && onDelete != null) onDelete!();
              },
              itemBuilder: (_) => [
                if (canEdit)
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
                if (canApproveEdit)
                  PopupMenuItem(
                    value: 'approve_edit',
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, size: 16),
                        const SizedBox(width: 8),
                        Text(tr('approve_seller_edit', ref)),
                      ],
                    ),
                  ),
                if (canApproveEdit)
                  PopupMenuItem(
                    value: 'reject_edit',
                    child: Row(
                      children: [
                        const Icon(Icons.cancel, size: 16),
                        const SizedBox(width: 8),
                        Text(tr('reject_seller_edit', ref)),
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
  final double? runningBalance;
  const _TxListItem({this.monthHeader, this.tx, this.runningBalance});
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

// _ReturnSheet removed — use void-invoice or Cash In/Out with description for adjustments.
