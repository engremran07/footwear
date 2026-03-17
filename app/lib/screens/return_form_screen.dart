import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/return_provider.dart';
import '../providers/auth_provider.dart';
import '../models/order_return_model.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_message.dart';

class ReturnFormScreen extends ConsumerStatefulWidget {
  const ReturnFormScreen({super.key});

  @override
  ConsumerState<ReturnFormScreen> createState() => _ReturnFormScreenState();
}

class _ReturnFormScreenState extends ConsumerState<ReturnFormScreen> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;

  // Step 1 — order selection
  String? _selectedOrderId;
  String? _selectedCustomerId;
  String _selectedCustomerName = '';
  List<Map<String, dynamic>> _orderItems = [];

  // Step 2 — line items
  // Map of orderItemId → ReturnItemDraft
  final Map<String, _ReturnItemDraft> _drafts = {};

  // Step 3 — return meta
  String _returnType = 'partial_return';
  final _refundController = TextEditingController();
  final _notesController = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _refundController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ─── Delivered orders stream ────────────────────────────────────────────────
  // Uses deliveredOrdersProvider from return_provider.dart

  Future<void> _loadOrderItems(String orderId) async {
    final items = await ref.read(dispatchedOrderItemsProvider(orderId).future);

    setState(() {
      _orderItems = items;
      _drafts.clear();
      for (final item in _orderItems) {
        _drafts[item['id'] as String] = _ReturnItemDraft(
          orderItemId: item['id'] as String,
          productId: item['product_id'] as String? ?? '',
          productName: item['product_name'] as String? ?? '',
          size: item['size'] as String? ?? '',
          maxQty: (item['qty'] as num?)?.toInt() ?? 1,
        );
      }
    });
  }

  void _addQty(String itemId, int delta) {
    setState(() {
      final d = _drafts[itemId]!;
      final newQty = (d.qtyReturned + delta).clamp(0, d.maxQty);
      _drafts[itemId] = d.copyWith(qtyReturned: newQty);
    });
  }

  List<_ReturnItemDraft> get _selectedDrafts =>
      _drafts.values.where((d) => d.qtyReturned > 0).toList();

  int get _totalQty => _selectedDrafts.fold(0, (sum, d) => sum + d.qtyReturned);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDrafts.isEmpty) {
      AppMessage.warning(context, ref, 'select_items_return');
      return;
    }

    setState(() => _submitting = true);
    final user = ref.read(authUserProvider).valueOrNull;

    final items = _selectedDrafts
        .map((d) => ReturnItem(
              orderItemId: d.orderItemId,
              productId: d.productId,
              productName: d.productName,
              size: d.size,
              qtyReturned: d.qtyReturned,
              condition: d.condition,
              reason: d.reason,
            ).toMap())
        .toList();

    try {
      await ref.read(returnNotifierProvider.notifier).create({
        'order_id': _selectedOrderId,
        'customer_id': _selectedCustomerId,
        'customer_name': _selectedCustomerName,
        'type': _returnType,
        'items': items,
        'total_qty_returned': _totalQty,
        'refund_amount': double.tryParse(_refundController.text.trim()) ?? 0.0,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'created_by': user?.id ?? '',
      });
      if (mounted) {
        AppMessage.success(context, ref, 'return_submitted');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null || !user.canWrite) {
      return Scaffold(body: Center(child: Text(tr('access_denied', ref))));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('new_return', ref)),
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _step,
          onStepContinue: () {
            if (_step == 0) {
              if (_selectedOrderId == null) {
                AppMessage.warning(context, ref, 'select_please');
                return;
              }
              setState(() => _step = 1);
            } else if (_step == 1) {
              if (_selectedDrafts.isEmpty) {
                AppMessage.warning(context, ref, 'select_items_return');
                return;
              }
              setState(() => _step = 2);
            } else {
              _submit();
            }
          },
          onStepCancel: () {
            if (_step > 0) setState(() => _step--);
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _submitting ? null : details.onStepContinue,
                    child: _step < 2
                        ? Text(tr('next', ref))
                        : _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(tr('submit', ref)),
                  ),
                  if (_step > 0) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: Text(tr('back', ref)),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            Step(
              title: Text(tr('select_order', ref)),
              isActive: _step >= 0,
              state: _step > 0 ? StepState.complete : StepState.indexed,
              content: _Step1OrderPicker(
                selectedOrderId: _selectedOrderId,
                onSelected: (orderId, customerId, customerName) {
                  setState(() {
                    _selectedOrderId = orderId;
                    _selectedCustomerId = customerId;
                    _selectedCustomerName = customerName;
                  });
                  _loadOrderItems(orderId);
                },
              ),
            ),
            Step(
              title: Text(tr('select_items', ref)),
              isActive: _step >= 1,
              state: _step > 1 ? StepState.complete : StepState.indexed,
              content: _Step2ItemSelection(
                orderItems: _orderItems,
                drafts: _drafts,
                onAddQty: _addQty,
                onConditionChanged: (id, val) => setState(
                    () => _drafts[id] = _drafts[id]!.copyWith(condition: val)),
                onReasonChanged: (id, val) => setState(
                    () => _drafts[id] = _drafts[id]!.copyWith(reason: val)),
              ),
            ),
            Step(
              title: Text(tr('return_details', ref)),
              isActive: _step >= 2,
              state: StepState.indexed,
              content: _Step3ReturnMeta(
                returnType: _returnType,
                refundController: _refundController,
                notesController: _notesController,
                totalQty: _totalQty,
                onTypeChanged: (val) =>
                    setState(() => _returnType = val ?? 'partial_return'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 1 — Order picker ──────────────────────────────────────────────────

class _Step1OrderPicker extends ConsumerWidget {
  final String? selectedOrderId;
  final void Function(String orderId, String customerId, String customerName)
      onSelected;

  const _Step1OrderPicker({
    required this.selectedOrderId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(deliveredOrdersProvider);
    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('${tr('error', ref)}: $e'),
      data: (orders) {
        if (orders.isEmpty) {
          return Text(tr('no_delivered_orders', ref));
        }
        return DropdownButtonFormField<String>(
          initialValue: selectedOrderId,
          decoration: InputDecoration(
            labelText: tr('delivered_order', ref),
            border: const OutlineInputBorder(),
          ),
          items: orders
              .map((o) => DropdownMenuItem<String>(
                    value: o['id'] as String,
                    child: Text(
                        '${o['customer_name']} — ${(o['id'] as String).substring(0, 8)}…'),
                  ))
              .toList(),
          onChanged: (id) {
            if (id == null) return;
            final order = orders.firstWhere((o) => o['id'] == id);
            onSelected(
              id,
              order['customer_id'] as String? ?? '',
              order['customer_name'] as String? ?? '',
            );
          },
          validator: (v) => v == null ? tr('select_please', ref) : null,
        );
      },
    );
  }
}

// ─── Step 2 — Item selection ────────────────────────────────────────────────

class _Step2ItemSelection extends ConsumerWidget {
  final List<Map<String, dynamic>> orderItems;
  final Map<String, _ReturnItemDraft> drafts;
  final void Function(String id, int delta) onAddQty;
  final void Function(String id, String val) onConditionChanged;
  final void Function(String id, String val) onReasonChanged;

  const _Step2ItemSelection({
    required this.orderItems,
    required this.drafts,
    required this.onAddQty,
    required this.onConditionChanged,
    required this.onReasonChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orderItems.isEmpty) {
      return Text(tr('select_order_first', ref));
    }
    return Column(
      children: orderItems.map((item) {
        final id = item['id'] as String;
        final draft = drafts[id];
        if (draft == null) return const SizedBox.shrink();
        return _ItemSelectionRow(
          draft: draft,
          onAddQty: (delta) => onAddQty(id, delta),
          onConditionChanged: (val) => onConditionChanged(id, val),
          onReasonChanged: (val) => onReasonChanged(id, val),
        );
      }).toList(),
    );
  }
}

class _ItemSelectionRow extends ConsumerWidget {
  final _ReturnItemDraft draft;
  final void Function(int delta) onAddQty;
  final void Function(String val) onConditionChanged;
  final void Function(String val) onReasonChanged;

  const _ItemSelectionRow({
    required this.draft,
    required this.onAddQty,
    required this.onConditionChanged,
    required this.onReasonChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${draft.productName} — Size ${draft.size}',
                style: Theme.of(context).textTheme.titleSmall),
            Text(
                '${tr('max_returnable', ref)}: ${draft.maxQty} ${tr('pairs', ref)}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            // Qty controls
            Row(
              children: [
                Text('${tr('qty', ref)}: '),
                _QtyChip(label: '+1', onTap: () => onAddQty(1)),
                _QtyChip(label: '+12', onTap: () => onAddQty(12)),
                _QtyChip(label: '+20', onTap: () => onAddQty(20)),
                if (draft.qtyReturned > 0) ...[
                  _QtyChip(label: '-1', onTap: () => onAddQty(-1)),
                ],
                const SizedBox(width: 8),
                Text(
                  '${draft.qtyReturned} ${tr('pairs', ref)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (draft.qtyReturned > 0) ...[
              const SizedBox(height: 8),
              // Condition
              DropdownButton<String>(
                value: draft.condition,
                onChanged: (v) => onConditionChanged(v!),
                items: [
                  DropdownMenuItem(
                      value: 'good', child: Text(tr('condition_good', ref))),
                  DropdownMenuItem(
                      value: 'damaged',
                      child: Text(tr('condition_damaged', ref))),
                ],
              ),
              const SizedBox(height: 4),
              // Reason
              DropdownButton<String>(
                value: draft.reason,
                onChanged: (v) => onReasonChanged(v!),
                items: [
                  DropdownMenuItem(
                      value: 'wrong_size',
                      child: Text(tr('reason_wrong_size', ref))),
                  DropdownMenuItem(
                      value: 'stitching_issue',
                      child: Text(tr('reason_stitching_issue', ref))),
                  DropdownMenuItem(
                      value: 'sole_defect',
                      child: Text(tr('reason_sole_defect', ref))),
                  DropdownMenuItem(
                      value: 'wrong_item',
                      child: Text(tr('reason_wrong_item', ref))),
                  DropdownMenuItem(
                      value: 'cosmetic',
                      child: Text(tr('reason_cosmetic', ref))),
                  DropdownMenuItem(
                      value: 'other', child: Text(tr('reason_other', ref))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QtyChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QtyChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ─── Step 3 — Return type + refund ──────────────────────────────────────────

class _Step3ReturnMeta extends ConsumerWidget {
  final String returnType;
  final TextEditingController refundController;
  final TextEditingController notesController;
  final int totalQty;
  final void Function(String?) onTypeChanged;

  const _Step3ReturnMeta({
    required this.returnType,
    required this.refundController,
    required this.notesController,
    required this.totalQty,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${tr('total_pairs_return', ref)}: $totalQty',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: returnType,
          decoration: InputDecoration(
            labelText: tr('return_type', ref),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
                value: 'full_return', child: Text(tr('return_type_full', ref))),
            DropdownMenuItem(
                value: 'partial_return',
                child: Text(tr('return_type_partial', ref))),
            DropdownMenuItem(
                value: 'replacement',
                child: Text(tr('return_type_replacement', ref))),
            DropdownMenuItem(
                value: 'damage_claim',
                child: Text(tr('return_type_damage_claim', ref))),
          ],
          onChanged: onTypeChanged,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: refundController,
          decoration: InputDecoration(
            labelText: tr('refund_amount', ref),
            border: const OutlineInputBorder(),
            prefixText: 'SAR ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return tr('enter_refund_amount', ref);
            }
            if (double.tryParse(v.trim()) == null) {
              return tr('invalid_amount', ref);
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: notesController,
          decoration: InputDecoration(
            labelText: tr('notes_optional', ref),
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        Text(
          tr('cash_refund_note', ref),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade700,
              ),
        ),
      ],
    );
  }
}

// ─── Draft helper class ──────────────────────────────────────────────────────

class _ReturnItemDraft {
  final String orderItemId;
  final String productId;
  final String productName;
  final String size;
  final int maxQty;
  final int qtyReturned;
  final String condition;
  final String reason;

  const _ReturnItemDraft({
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.size,
    required this.maxQty,
    this.qtyReturned = 0,
    this.condition = 'good',
    this.reason = 'other',
  });

  _ReturnItemDraft copyWith({
    int? qtyReturned,
    String? condition,
    String? reason,
  }) {
    return _ReturnItemDraft(
      orderItemId: orderItemId,
      productId: productId,
      productName: productName,
      size: size,
      maxQty: maxQty,
      qtyReturned: qtyReturned ?? this.qtyReturned,
      condition: condition ?? this.condition,
      reason: reason ?? this.reason,
    );
  }
}
