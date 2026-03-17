import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/approval_provider.dart';
import '../providers/cash_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/auth_provider.dart';
import '../models/cash_approval_model.dart';
import '../models/expense_approval_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/status_chip.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/utils/app_message.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cashApprovals = ref.watch(allPendingCashApprovalsProvider);
    final expenseApprovals = ref.watch(allPendingExpenseApprovalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('approvals', ref)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: tr('export_share', ref),
            onPressed: () {
              final cashList = cashApprovals.valueOrNull ?? [];
              final expList = expenseApprovals.valueOrNull ?? [];
              ExportSheet.show(
                context,
                ref,
                title: 'Approvals',
                fileName: 'pending_approvals',
                headers: [
                  'Type',
                  'Reference/Category',
                  'Amount',
                  'Status',
                  'Created At'
                ],
                rows: [
                  ...cashList.map((a) => [
                        'Cash: ${a.type}',
                        a.reference,
                        a.amount,
                        a.status,
                        AppFormatters.date(a.createdAt),
                      ]),
                  ...expList.map((a) => [
                        'Expense',
                        '${a.category} — ${a.description}',
                        a.amount,
                        a.status,
                        AppFormatters.date(a.createdAt),
                      ]),
                ],
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppBrand.onPrimary,
          unselectedLabelColor: AppBrand.onPrimaryMuted,
          indicatorColor: AppBrand.onPrimary,
          tabs: [
            Tab(
              text:
                  '${tr('cash', ref)} (${cashApprovals.valueOrNull?.length ?? 0})',
            ),
            Tab(
              text:
                  '${tr('expenses', ref)} (${expenseApprovals.valueOrNull?.length ?? 0})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CashApprovalList(approvals: cashApprovals),
          _ExpenseApprovalList(approvals: expenseApprovals),
        ],
      ),
    );
  }
}

class _CashApprovalList extends ConsumerWidget {
  final AsyncValue<List<CashApprovalModel>> approvals;
  const _CashApprovalList({required this.approvals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return approvals.when(
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            message: tr('no_pending_cash_approvals', ref),
            icon: Icons.check_circle_outline,
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => _CashApprovalTile(approval: list[i]),
        );
      },
      loading: () => const ShimmerLoading(),
      error: (e, _) => ErrorState(message: e.toString()),
    );
  }
}

class _CashApprovalTile extends ConsumerWidget {
  final CashApprovalModel approval;
  const _CashApprovalTile({required this.approval});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(approval.reference,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                StatusChip(status: approval.type),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              AppFormatters.sar(approval.amount),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(AppFormatters.date(approval.createdAt),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => _reject(context, ref),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _approve(context, ref),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(cashNotifierProvider.notifier)
          .approveCashApproval(approval.id, user.id);
      if (context.mounted) {
        AppMessage.success(context, ref, 'success_approved');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(cashNotifierProvider.notifier)
          .rejectCashApproval(approval.id, user.id, '');
      if (context.mounted) {
        AppMessage.success(context, ref, 'success_rejected');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }
}

class _ExpenseApprovalList extends ConsumerWidget {
  final AsyncValue<List<ExpenseApprovalModel>> approvals;
  const _ExpenseApprovalList({required this.approvals});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return approvals.when(
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            message: tr('no_pending_expense_approvals', ref),
            icon: Icons.check_circle_outline,
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => _ExpenseApprovalTile(approval: list[i]),
        );
      },
      loading: () => const ShimmerLoading(),
      error: (e, _) => ErrorState(message: e.toString()),
    );
  }
}

class _ExpenseApprovalTile extends ConsumerWidget {
  final ExpenseApprovalModel approval;
  const _ExpenseApprovalTile({required this.approval});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(approval.description,
                        style: Theme.of(context).textTheme.titleSmall)),
                StatusChip(status: approval.category),
              ],
            ),
            const SizedBox(height: 4),
            Text(AppFormatters.sar(approval.amount),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(AppFormatters.date(approval.createdAt),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => _reject(context, ref),
                  child: Text(tr('reject', ref)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _approve(context, ref),
                  child: Text(tr('approve', ref)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(expenseNotifierProvider.notifier)
          .approveExpenseApproval(approval.id, user.id);
      if (context.mounted) {
        AppMessage.success(context, ref, 'success_approved');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref
          .read(expenseNotifierProvider.notifier)
          .rejectExpenseApproval(approval.id, user.id, '');
      if (context.mounted) {
        AppMessage.success(context, ref, 'success_rejected');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }
}
