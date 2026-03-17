import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/return_provider.dart';
import '../providers/auth_provider.dart';
import '../models/order_return_model.dart';
import '../models/user_model.dart';
import '../widgets/error_state.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_message.dart';

class ReturnDetailScreen extends ConsumerWidget {
  final String returnId;

  const ReturnDetailScreen({super.key, required this.returnId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReturn = ref.watch(returnDetailProvider(returnId));
    final user = ref.watch(authUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('return_detail', ref)),
      ),
      body: asyncReturn.when(
        data: (ret) {
          if (ret == null) {
            return Center(child: Text(tr('return_not_found', ref)));
          }
          return _ReturnDetailBody(ret: ret, user: user, ref: ref);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
    );
  }
}

class _ReturnDetailBody extends StatelessWidget {
  final OrderReturnModel ret;
  final UserModel? user;
  final WidgetRef ref;

  const _ReturnDetailBody({
    required this.ret,
    required this.user,
    required this.ref,
  });

  String _label(String key) => key.replaceAll('_', ' ').toUpperCase();

  Color _statusColor(String status) {
    return switch (status) {
      'pending' => Colors.orange,
      'approved' => Colors.blue,
      'rejected' => Colors.red,
      'completed' => Colors.green,
      _ => Colors.grey,
    };
  }

  Future<void> _handleApprove(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('approve_return', ref)),
        content: Text(tr('approve_return_info', ref)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel', ref))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('approve', ref))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref
          .read(returnNotifierProvider.notifier)
          .approve(ret.id, user?.id ?? '');
      if (context.mounted) {
        AppMessage.success(context, ref, 'return_approved');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }

  Future<void> _handleReject(BuildContext context) async {
    final notesController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('reject_return', ref)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('reject_return_info', ref)),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: tr('reason_optional', ref),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel', ref))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('reject', ref))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref.read(returnNotifierProvider.notifier).reject(
            ret.id,
            user?.id ?? '',
            notes: notesController.text.trim().isEmpty
                ? null
                : notesController.text.trim(),
          );
      if (context.mounted) {
        AppMessage.success(context, ref, 'return_rejected');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }

  Future<void> _handleComplete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('mark_as_completed', ref)),
        content: Text(tr('mark_completed_info', ref)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel', ref))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('mark_complete', ref))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await ref.read(returnNotifierProvider.notifier).complete(ret.id);
      if (context.mounted) {
        AppMessage.success(context, ref, 'return_completed_log');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        DateFormat('dd MMM yyyy, HH:mm').format(ret.createdAt.toDate());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status badge ──────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(ret.status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  ret.status.toUpperCase(),
                  style: TextStyle(
                    color: _statusColor(ret.status),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),

          // ── Summary card ──────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(tr('customer', ref), ret.customerName),
                  _DetailRow(
                      tr('order_id_label', ref),
                      ret.orderId.length > 12
                          ? '${ret.orderId.substring(0, 12)}…'
                          : ret.orderId),
                  _DetailRow(tr('return_type', ref), _label(ret.type)),
                  _DetailRow(
                      tr('total_pairs', ref), '${ret.totalQtyReturned} pairs'),
                  _DetailRow(tr('refund_amount', ref),
                      'SAR ${ret.refundAmount.toStringAsFixed(2)}'),
                  if (ret.notes != null && ret.notes!.isNotEmpty)
                    _DetailRow(tr('notes', ref), ret.notes!),
                  if (ret.replacementOrderId != null)
                    _DetailRow(
                        tr('replacement_order', ref), ret.replacementOrderId!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Items list ────────────────────────────────────────────────────
          Text(tr('items', ref),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...ret.items.map((item) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    item.condition == 'good'
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: item.condition == 'good' ? Colors.green : Colors.red,
                  ),
                  title: Text('${item.productName} — Size ${item.size}'),
                  subtitle: Text(
                      '${item.qtyReturned} pairs · ${item.condition.toUpperCase()} · ${item.reason.replaceAll('_', ' ')}'),
                ),
              )),

          const SizedBox(height: 24),

          // ── Action buttons ────────────────────────────────────────────────
          // Immutable states: completed and rejected show nothing
          if (!ret.isCompleted && !ret.isRejected) ...[
            // Admin can approve/reject pending returns
            if (ret.isPending && (user?.isAdmin ?? false)) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleApprove(context),
                      icon: const Icon(Icons.check),
                      label: Text(tr('approve', ref)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleReject(context),
                      icon: const Icon(Icons.close),
                      label: Text(tr('reject', ref)),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
            // Manager can mark approved return as complete (after physical refund)
            if (ret.isApproved && (user?.isManager ?? false)) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _handleComplete(context),
                  icon: const Icon(Icons.done_all),
                  label: Text(tr('mark_as_completed', ref)),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('reminder_cash_refund', ref),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],

          if (ret.isCompleted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Text(
                tr('return_locked', ref),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.green),
              ),
            ),

          if (ret.isRejected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Text(
                tr('return_rejected_msg', ref),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
