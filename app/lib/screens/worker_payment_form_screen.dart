import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/worker_provider.dart';
import '../providers/auth_provider.dart';
import '../core/utils/validators.dart';
import '../core/utils/formatters.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class WorkerPaymentFormScreen extends ConsumerStatefulWidget {
  final String workerId;
  const WorkerPaymentFormScreen({super.key, required this.workerId});

  @override
  ConsumerState<WorkerPaymentFormScreen> createState() =>
      _WorkerPaymentFormScreenState();
}

class _WorkerPaymentFormScreenState
    extends ConsumerState<WorkerPaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _pairsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _period = AppFormatters.currentPeriod();
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _pairsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final worker = ref.read(workerDetailProvider(widget.workerId)).valueOrNull;
    if (worker == null) return;

    setState(() => _loading = true);
    try {
      await ref.read(workerNotifierProvider.notifier).createPayment({
        'worker_id': widget.workerId,
        'worker_name': worker.name,
        'worker_type': worker.type,
        'amount': double.parse(_amountCtrl.text.trim()),
        'pairs_count': int.parse(_pairsCtrl.text.trim()),
        'period': _period,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      });
      if (mounted) {
        AppMessage.success(context, ref, 'success_payment_recorded');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null || !user.canWrite) {
      return Scaffold(body: Center(child: Text(tr('access_denied', ref))));
    }
    final worker = ref.watch(workerDetailProvider(widget.workerId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(tr('create_payment', ref))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (worker != null) ...[
                Text('${tr('worker', ref)}: ${worker.name}',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                    'Rate: ${AppFormatters.currency(worker.ratePerPair, worker.currency)}/pair',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],
              TextFormField(
                initialValue: _period,
                decoration:
                    InputDecoration(labelText: '${tr('period', ref)} *'),
                validator: AppValidators.required('Period'),
                onChanged: (v) => _period = v.trim(),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pairsCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: '${tr('pairs_count', ref)} *'),
                validator: AppValidators.positiveInt,
                onChanged: (v) {
                  if (worker != null) {
                    final pairs = int.tryParse(v) ?? 0;
                    _amountCtrl.text =
                        (pairs * worker.ratePerPair).toStringAsFixed(2);
                    setState(() {});
                  }
                },
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${tr('amount', ref)} *',
                  suffixText: worker?.currency ?? '',
                ),
                validator: AppValidators.positiveNumber,
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration:
                    InputDecoration(labelText: tr('notes_optional', ref)),
                maxLines: 2,
                enabled: !_loading,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(tr('submit_payment', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
