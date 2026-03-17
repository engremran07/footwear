import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/cash_provider.dart';
import '../providers/auth_provider.dart';
import '../models/cash_transaction_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/status_chip.dart';
import '../core/utils/formatters.dart';
import '../core/utils/validators.dart';
import '../widgets/export_sheet.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(cashTransactionsProvider);

    double totalIn = 0;
    double totalOut = 0;
    transactions.valueOrNull?.forEach((t) {
      if (t.status == 'approved') {
        if (t.type == 'cash_in') {
          totalIn += t.amount;
        } else {
          totalOut += t.amount;
        }
      }
    });
    final balance = totalIn - totalOut;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('cash', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = transactions.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Cash Transactions',
                fileName: 'cash_transactions',
                headers: [
                  'Reference',
                  'Type',
                  'Amount',
                  'P&L Category',
                  'Description',
                  'Status',
                  'Created At'
                ],
                rows: data
                    .map((t) => [
                          t.reference,
                          t.type,
                          t.amount,
                          t.pnlCategory,
                          t.description ?? '',
                          t.status,
                          AppFormatters.date(t.createdAt)
                        ])
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _CashSummary(
            balance: balance,
            totalIn: totalIn,
            totalOut: totalOut,
          ),
          const Divider(height: 1),
          Expanded(
            child: transactions.when(
              data: (list) => list.isEmpty
                  ? EmptyState(
                      message: tr('no_transactions_yet', ref),
                      icon: Icons.attach_money,
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => _TransactionTile(tx: list[i]),
                    ),
              loading: () => const ShimmerLoading(),
              error: (e, _) => ErrorState(message: e.toString()),
            ),
          ),
        ],
      ),
      floatingActionButton:
          (ref.watch(authUserProvider).valueOrNull?.canWrite ?? false)
              ? FloatingActionButton(
                  onPressed: () => _showAddDialog(context),
                  child: const Icon(Icons.add),
                )
              : null,
    );
  }

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddTransactionSheet(
        onSubmit: (data) async {
          final user = ref.read(authUserProvider).valueOrNull;
          if (user == null) return;
          await ref
              .read(cashNotifierProvider.notifier)
              .addTransaction(data, user.id);
        },
      ),
    );
  }
}

class _CashSummary extends ConsumerWidget {
  final double balance;
  final double totalIn;
  final double totalOut;

  const _CashSummary({
    required this.balance,
    required this.totalIn,
    required this.totalOut,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.primaryContainer,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('balance', ref),
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
                Text(
                  AppFormatters.sar(balance),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: balance >= 0
                        ? Colors.green.shade700
                        : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${tr('cash_in', ref)}: ${AppFormatters.sar(totalIn)}',
                  style: const TextStyle(color: Colors.green)),
              Text('${tr('cash_out', ref)}: ${AppFormatters.sar(totalOut)}',
                  style: const TextStyle(color: Colors.red)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final CashTransactionModel tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCashIn = tx.type == 'cash_in';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCashIn ? Colors.green.shade100 : Colors.red.shade100,
        child: Icon(
          isCashIn ? Icons.arrow_downward : Icons.arrow_upward,
          color: isCashIn ? Colors.green : Colors.red,
        ),
      ),
      title: Text(tx.reference),
      subtitle: Text('${tx.pnlCategory} · ${AppFormatters.date(tx.createdAt)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            (isCashIn ? '+' : '-') + AppFormatters.sar(tx.amount),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isCashIn ? Colors.green : Colors.red,
            ),
          ),
          StatusChip(status: tx.status),
        ],
      ),
    );
  }
}

class _AddTransactionSheet extends ConsumerStatefulWidget {
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  const _AddTransactionSheet({required this.onSubmit});

  @override
  ConsumerState<_AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<_AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String _type = 'cash_in';
  String _pnlCategory = 'revenue';
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('add_transaction', ref),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'cash_in', label: Text(tr('cash_in', ref))),
                ButtonSegment(
                    value: 'cash_out', label: Text(tr('cash_out', ref))),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _pnlCategory = s.first == 'cash_in' ? 'revenue' : 'expenses';
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  InputDecoration(labelText: '${tr('amount_sar', ref)} *'),
              validator: AppValidators.positiveNumber,
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _refCtrl,
              decoration:
                  InputDecoration(labelText: '${tr('reference_desc', ref)} *'),
              validator: AppValidators.required('Reference'),
              enabled: !_loading,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _pnlCategory,
              decoration:
                  InputDecoration(labelText: '${tr('pnl_category', ref)} *'),
              items: [
                DropdownMenuItem(
                    value: 'revenue', child: Text(tr('revenue', ref))),
                DropdownMenuItem(value: 'cogs', child: Text(tr('cogs', ref))),
                DropdownMenuItem(
                    value: 'expenses', child: Text(tr('expenses', ref))),
                DropdownMenuItem(
                    value: 'worker_cost', child: Text(tr('worker_cost', ref))),
                DropdownMenuItem(value: 'fuel', child: Text(tr('fuel', ref))),
                DropdownMenuItem(value: 'food', child: Text(tr('food', ref))),
                DropdownMenuItem(
                    value: 'accommodation',
                    child: Text(tr('accommodation', ref))),
                DropdownMenuItem(value: 'other', child: Text(tr('other', ref))),
              ],
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _pnlCategory = v ?? 'revenue'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _loading
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _loading = true);
                        try {
                          await widget.onSubmit({
                            'type': _type,
                            'amount': double.parse(_amountCtrl.text.trim()),
                            'reference': _refCtrl.text.trim(),
                            'pnl_category': _pnlCategory,
                          });
                          if (context.mounted) {
                            AppMessage.success(
                                context, ref, 'success_cash_recorded');
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            AppMessage.error(context, ref, e);
                          }
                        } finally {
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(tr('add_transaction', ref)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
