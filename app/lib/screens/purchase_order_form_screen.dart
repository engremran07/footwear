import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../providers/supplier_provider.dart';
import '../providers/product_provider.dart';
import '../core/utils/validators.dart';
import '../core/utils/formatters.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class PurchaseOrderFormScreen extends ConsumerStatefulWidget {
  const PurchaseOrderFormScreen({super.key});

  @override
  ConsumerState<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState
    extends ConsumerState<PurchaseOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _supplierId;
  String? _supplierName;
  DateTime? _expectedDelivery;
  final _notesCtrl = TextEditingController();
  final List<_LineItem> _items = [_LineItem()];
  bool _saving = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() => setState(() => _items.add(_LineItem()));

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  double get _total => _items.fold(
      0,
      (acc, item) =>
          acc +
          (double.tryParse(item.unitCostCtrl.text) ?? 0) *
              (int.tryParse(item.qtyCtrl.text) ?? 0));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_supplierId == null) {
      AppMessage.warning(context, ref, 'select_supplier');
      return;
    }
    if (_items.any((i) => i.productId == null)) {
      AppMessage.warning(context, ref, 'select_product_all');
      return;
    }
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final itemMaps = _items
          .map((i) => {
                'product_id': i.productId!,
                'product_name': i.productName ?? '',
                'sku': i.sku ?? '',
                'size': i.sizeCtrl.text.trim(),
                'qty': int.tryParse(i.qtyCtrl.text) ?? 0,
                'unit_cost': double.tryParse(i.unitCostCtrl.text) ?? 0.0,
              })
          .toList();

      await ref.read(purchaseOrderNotifierProvider.notifier).create({
        'supplier_id': _supplierId,
        'supplier_name': _supplierName,
        'items': itemMaps,
        'total': _total,
        'expected_delivery': _expectedDelivery != null
            ? Timestamp.fromDate(_expectedDelivery!)
            : null,
        'notes': _notesCtrl.text.trim(),
      }, user.id);
      if (mounted) {
        AppMessage.success(context, ref, 'success_created');
        context.pop();
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
    final suppliers = ref.watch(suppliersProvider);
    final products = ref.watch(allProductsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('new_purchase_order', ref))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            suppliers.when(
              data: (list) => DropdownButtonFormField<String>(
                decoration:
                    InputDecoration(labelText: '${tr('supplier', ref)} *'),
                initialValue: _supplierId,
                items: list
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _supplierId = v;
                    _supplierName = list
                        .firstWhere((s) => s.id == v, orElse: () => list.first)
                        .name;
                  });
                },
                validator: (v) => v == null ? tr('required_field', ref) : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('${tr('error', ref)}: $e'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_expectedDelivery == null
                  ? '${tr('expected_delivery', ref)}: ${tr('not_set', ref)}'
                  : '${tr('expected_delivery', ref)}: ${AppFormatters.date(Timestamp.fromDate(_expectedDelivery!))}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _expectedDelivery = d);
              },
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
            Text(tr('line_items', ref),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(
              _items.length,
              (i) => _LineItemWidget(
                item: _items[i],
                products: products.valueOrNull ?? [],
                index: i,
                canRemove: _items.length > 1,
                onRemove: () => _removeItem(i),
                onChanged: () => setState(() {}),
              ),
            ),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: Text(tr('add_item', ref)),
            ),
            const SizedBox(height: 8),
            Text('${tr('total', ref)}: ${AppFormatters.sar(_total)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('create_purchase_order', ref)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineItem {
  String? productId;
  String? productName;
  String? sku;
  final sizeCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final unitCostCtrl = TextEditingController();

  void dispose() {
    sizeCtrl.dispose();
    qtyCtrl.dispose();
    unitCostCtrl.dispose();
  }
}

class _LineItemWidget extends ConsumerWidget {
  final _LineItem item;
  final List<dynamic> products;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _LineItemWidget({
    required this.item,
    required this.products,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${tr('item_prefix', ref)} ${index + 1}',
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (canRemove)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onRemove,
                  ),
              ],
            ),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                  labelText: '${tr('product', ref)} *', isDense: true),
              initialValue: item.productId,
              items: products
                  .map((p) => DropdownMenuItem(
                        value: p.id as String,
                        child: Text('${p.name} (${p.sku})'),
                      ))
                  .toList(),
              onChanged: (v) {
                final p = products.firstWhere((x) => x.id == v,
                    orElse: () => products.first);
                item.productId = v;
                item.productName = p.name as String?;
                item.sku = p.sku as String?;
                onChanged();
              },
              validator: (v) => v == null ? tr('required', ref) : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.sizeCtrl,
                    decoration: InputDecoration(
                        labelText: tr('size', ref), isDense: true),
                    validator: Validators.notEmpty,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: item.qtyCtrl,
                    decoration: InputDecoration(
                        labelText: tr('qty', ref), isDense: true),
                    keyboardType: TextInputType.number,
                    validator: Validators.positiveInt,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: item.unitCostCtrl,
                    decoration: InputDecoration(
                        labelText: tr('unit_cost', ref), isDense: true),
                    keyboardType: TextInputType.number,
                    validator: Validators.positiveDouble,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
