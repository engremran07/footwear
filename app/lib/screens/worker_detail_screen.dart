import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/worker_provider.dart';
import '../models/worker_model.dart';
import '../models/worker_payment_model.dart';
import '../widgets/status_chip.dart';
import '../widgets/role_guard.dart';
import '../core/utils/formatters.dart';
import '../core/l10n/app_locale.dart';

class WorkerDetailScreen extends ConsumerWidget {
  final String workerId;
  const WorkerDetailScreen({super.key, required this.workerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final worker = ref.watch(workerDetailProvider(workerId));
    final payments = ref.watch(workerPaymentsProvider(workerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('worker', ref)),
        actions: [
          RoleGuard(
            allowed: (u) => u.isAdmin,
            child: worker.when(
              data: (w) => w != null
                  ? IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => context.push('/workers/$workerId/edit'),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      body: worker.when(
        data: (w) {
          if (w == null) {
            return Center(child: Text(tr('worker_not_found', ref)));
          }
          return Column(
            children: [
              _WorkerHeader(worker: w, workerId: workerId),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(tr('payment_history', ref),
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    RoleGuard(
                      allowed: (u) => u.isManager,
                      child: TextButton.icon(
                        icon: const Icon(Icons.payment),
                        label: Text(tr('pay', ref)),
                        onPressed: () => context.push('/workers/$workerId/pay'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: payments.when(
                  data: (list) => list.isEmpty
                      ? Center(child: Text(tr('no_payments_yet', ref)))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) => _PaymentTile(payment: list[i]),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text('${tr('error', ref)}: $e')),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${tr('error', ref)}: $e')),
      ),
    );
  }
}

class _WorkerHeader extends ConsumerWidget {
  final WorkerModel worker;
  final String workerId;
  const _WorkerHeader({required this.worker, required this.workerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(worker.name[0].toUpperCase(),
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(worker.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    '${worker.type.toUpperCase()} · ${worker.active ? tr('active', ref) : tr('inactive', ref)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            children: [
              _Stat(
                  label: tr('rate_per_pair', ref),
                  value: AppFormatters.currency(
                      worker.ratePerPair, worker.currency)),
              _Stat(
                  label: tr('total_earned', ref),
                  value: AppFormatters.currency(
                      worker.totalEarned, worker.currency)),
              _Stat(
                  label: tr('pairs_produced', ref),
                  value: worker.pairsProduced.toString()),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final WorkerPaymentModel payment;
  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.payment)),
      title: Text(AppFormatters.currency(
          payment.amount, payment.workerType == 'pk' ? 'PKR' : 'SAR')),
      subtitle: Text('${payment.pairsCount} pairs · ${payment.period}'),
      trailing: StatusChip(status: payment.status),
    );
  }
}
