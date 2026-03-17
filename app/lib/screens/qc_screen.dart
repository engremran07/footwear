import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/qc_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../models/inventory_batch_model.dart';
import '../models/settings_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/status_chip.dart';
import '../core/utils/validators.dart';
import '../core/utils/formatters.dart';
import '../widgets/export_sheet.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class QcScreen extends ConsumerWidget {
  const QcScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(qcPendingBatchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('quality_control', ref)),
        actions: [
          if (batches.valueOrNull != null && batches.valueOrNull!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: tr('export_share', ref),
              onPressed: () {
                final list = batches.valueOrNull!;
                ExportSheet.show(
                  context,
                  ref,
                  title: 'QC Batches',
                  fileName: 'qc_pending_batches',
                  headers: [
                    tr('batch_prefix', ref),
                    tr('product', ref),
                    tr('qty_produced', ref),
                    tr('status', ref),
                    tr('created_at', ref)
                  ],
                  rows: list
                      .map((b) => [
                            b.id,
                            b.productId,
                            b.qtyProduced,
                            b.status,
                            AppFormatters.date(b.createdAt),
                          ])
                      .toList(),
                );
              },
            ),
        ],
      ),
      body: batches.when(
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              message: tr('no_batches_pending_qc', ref),
              icon: Icons.check_circle_outline,
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => _QcBatchTile(batch: list[i]),
          );
        },
        loading: () => const ShimmerLoading(),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
    );
  }
}

class _QcBatchTile extends ConsumerWidget {
  final InventoryBatchModel batch;
  const _QcBatchTile({required this.batch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text('${tr('batch_prefix', ref)} ${batch.id.substring(0, 8)}…'),
        subtitle: Text(
            'Produced: ${batch.qtyProduced} pairs · ${AppFormatters.date(batch.createdAt)}'),
        trailing: StatusChip(status: batch.status),
        onTap: () => _showQcForm(context, ref, batch),
      ),
    );
  }

  void _showQcForm(
      BuildContext context, WidgetRef ref, InventoryBatchModel batch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QcSubmitSheet(batch: batch),
    );
  }
}

class _QcSubmitSheet extends ConsumerStatefulWidget {
  final InventoryBatchModel batch;
  const _QcSubmitSheet({required this.batch});

  @override
  ConsumerState<_QcSubmitSheet> createState() => _QcSubmitSheetState();
}

class _QcSubmitSheetState extends ConsumerState<_QcSubmitSheet> {
  final _formKey = GlobalKey<FormState>();
  final _passedCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_RejectedItem> _rejectedItems = [];
  bool _saving = false;

  @override
  void dispose() {
    _passedCtrl.dispose();
    _notesCtrl.dispose();
    for (final item in _rejectedItems) {
      item.dispose();
    }
    super.dispose();
  }

  int get _rejectedTotal => _rejectedItems.fold(
      0, (sum, item) => sum + (int.tryParse(item.qtyCtrl.text) ?? 0));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final passedQty = int.tryParse(_passedCtrl.text) ?? 0;
      final rejectedItems = _rejectedItems
          .map((r) => {
                'inventory_item_id': '',
                'size': r.sizeCtrl.text.trim(),
                'reason': r.reason,
              })
          .toList();

      await ref.read(qcNotifierProvider.notifier).submitQcRecord({
        'batch_id': widget.batch.id,
        'product_id': widget.batch.productId,
        'passed_qty': passedQty,
        'rejected_qty': _rejectedTotal,
        'rejected_items': rejectedItems,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'inspector': user.id,
      });
      if (mounted) {
        AppMessage.success(context, ref, 'success_qc_submitted');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).valueOrNull;
    final reasons = s?.qcRejectReasons ?? SettingsModel.defaultQcRejectReasons;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${tr('qc_record', ref)} — ${widget.batch.id.substring(0, 8)}…',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('${tr('total_produced', ref)}: ${widget.batch.qtyProduced}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passedCtrl,
                decoration: InputDecoration(
                    labelText: '${tr('passed_qty', ref)} *',
                    border: const OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: Validators.positiveInt,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                    labelText: tr('notes', ref),
                    border: const OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(tr('rejected_items', ref),
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _rejectedItems.add(_RejectedItem())),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(tr('add_btn', ref)),
                  ),
                ],
              ),
              ..._rejectedItems.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: r.sizeCtrl,
                          decoration: InputDecoration(
                              labelText: tr('size_label', ref), isDense: true),
                          validator: Validators.notEmpty,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: r.reason.isEmpty ? null : r.reason,
                          decoration: InputDecoration(
                              labelText: tr('reason_qc', ref), isDense: true),
                          items: reasons
                              .map((rs) =>
                                  DropdownMenuItem(value: rs, child: Text(rs)))
                              .toList(),
                          onChanged: (v) => setState(() => r.reason = v ?? ''),
                          validator: (v) => (v == null || v.isEmpty)
                              ? tr('required', ref)
                              : null,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          r.dispose();
                          _rejectedItems.remove(r);
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(tr('submit_qc', ref)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _RejectedItem {
  final sizeCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  String reason = '';

  void dispose() {
    sizeCtrl.dispose();
    qtyCtrl.dispose();
  }
}
