import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../models/expense_model.dart';
import '../models/settings_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/l10n/app_locale.dart';

class ExpensesListScreen extends ConsumerStatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  ConsumerState<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends ConsumerState<ExpensesListScreen> {
  String? _categoryFilter;
  String? _statusFilter;

  List<String> get _categories {
    final s = ref.watch(settingsProvider).valueOrNull;
    return s?.expenseCategories ?? SettingsModel.defaultExpenseCategories;
  }

  @override
  Widget build(BuildContext context) {
    final expenses = ref.watch(expensesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('expenses', ref)),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _categoryFilter = v),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: null, child: Text(tr('all_categories', ref))),
              ..._categories.map((c) => PopupMenuItem(
                    value: c,
                    child: Text(c.toUpperCase()),
                  )),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final data = expenses.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Expenses',
                fileName: 'expenses',
                headers: [
                  tr('category', ref),
                  tr('amount', ref),
                  tr('description', ref),
                  tr('status', ref),
                  tr('created_by', ref),
                  tr('created_at', ref)
                ],
                rows: data
                    .map((e) => [
                          e.category,
                          e.amount,
                          e.description,
                          e.status,
                          e.createdBy,
                          AppFormatters.date(e.createdAt)
                        ])
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: expenses.when(
        data: (list) {
          var filtered = list;
          if (_categoryFilter != null) {
            filtered =
                filtered.where((e) => e.category == _categoryFilter).toList();
          }
          if (_statusFilter != null) {
            filtered =
                filtered.where((e) => e.status == _statusFilter).toList();
          }
          if (filtered.isEmpty) {
            return EmptyState(
              message: tr('no_expenses_found', ref),
              icon: Icons.receipt_long_outlined,
            );
          }
          return ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => _ExpenseTile(expense: filtered[i]),
          );
        },
        loading: () => const ShimmerLoading(),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
      floatingActionButton: RoleGuard(
        allowed: (u) => u.isManager,
        child: FloatingActionButton(
          onPressed: () => context.push('/expenses/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final ExpenseModel expense;
  const _ExpenseTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
      title: Text(expense.description),
      subtitle: Text('${expense.category.toUpperCase()} · '
          '${AppFormatters.date(expense.createdAt)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(AppFormatters.sar(expense.amount),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          StatusChip(status: expense.status),
        ],
      ),
    );
  }
}
