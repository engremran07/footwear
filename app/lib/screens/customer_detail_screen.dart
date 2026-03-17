import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/customer_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/auth_provider.dart';
import '../models/customer_model.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_message.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerDetailProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('customer', ref)),
        actions: [
          RoleGuard(
            allowed: (u) => u.isManager,
            child: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => context.push('/customers/$customerId/edit'),
            ),
          ),
        ],
      ),
      body: customer.when(
        data: (c) {
          if (c == null) {
            return Center(child: Text(tr('customer_not_found', ref)));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 36,
                  child: Text(
                    c.name[0].toUpperCase(),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Chip(
                      label: Text(c.type.toUpperCase(),
                          style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 8),
                    Text(c.country,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
                const Divider(height: 24),
                _InfoRow(label: tr('phone', ref), value: c.phone),
                if (c.email != null)
                  _InfoRow(label: tr('email', ref), value: c.email!),
                if (c.address != null)
                  _InfoRow(label: tr('address', ref), value: c.address!),
                if (c.city != null)
                  _InfoRow(label: tr('city', ref), value: c.city!),
                if (c.area != null)
                  _InfoRow(label: tr('area', ref), value: c.area!),
                if (c.contactName != null)
                  _InfoRow(
                      label: tr('contact_name', ref), value: c.contactName!),
                if (c.sellerName != null)
                  _InfoRow(
                      label: tr('assigned_seller', ref), value: c.sellerName!),
                _InfoRow(
                    label: tr('total_orders', ref),
                    value: c.totalOrders.toString()),
                _InfoRow(
                    label: tr('balance', ref),
                    value: AppFormatters.sar(c.balance)),
                _InfoRow(
                    label: tr('member_since', ref),
                    value: AppFormatters.date(c.createdAt)),
                if (c.notes != null && c.notes!.isNotEmpty)
                  _InfoRow(label: tr('notes', ref), value: c.notes!),
                const SizedBox(height: 16),
                _BadDebtSection(customer: c),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${tr('error', ref)}: $e')),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
              child:
                  Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ─── Bad Debt Write-Off ───────────────────────────────────────────────────

class _BadDebtSection extends ConsumerStatefulWidget {
  final CustomerModel customer;
  const _BadDebtSection({required this.customer});

  @override
  ConsumerState<_BadDebtSection> createState() => _BadDebtSectionState();
}

class _BadDebtSectionState extends ConsumerState<_BadDebtSection> {
  bool _loading = false;

  Future<void> _writeOff(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('write_off_bad_debt', ref)),
        content: Text(
          tr('bad_debt_confirm_msg', ref),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel', ref)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('write_off', ref)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      await ref.read(expenseNotifierProvider.notifier).create({
        'category': 'bad_debt',
        'amount': widget.customer.balance,
        'description':
            'Bad debt write-off: ${widget.customer.name} (${widget.customer.id})',
        'receipt_url': null,
        'approved_by': null,
        'approved_at': null,
        'rejected_by': null,
        'rejected_at': null,
      }, user.id);

      await ref
          .read(customerNotifierProvider.notifier)
          .save(widget.customer.id, {'balance': 0.0});

      if (context.mounted) {
        AppMessage.success(context, ref, 'bad_debt_written_off');
      }
    } catch (e) {
      if (context.mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.customer.balance <= 0) return const SizedBox.shrink();
    return RoleGuard(
      allowed: (u) => u.isManager,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: _loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.money_off),
          label: Text(
              '${tr('write_off_amount_bad_debt', ref)}: ${AppFormatters.sar(widget.customer.balance)}'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(color: Theme.of(context).colorScheme.error),
          ),
          onPressed: _loading ? null : () => _writeOff(context),
        ),
      ),
    );
  }
}
