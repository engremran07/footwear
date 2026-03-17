import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/order_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/auth_provider.dart';
import '../core/utils/validators.dart';
import '../core/utils/formatters.dart';
import '../core/utils/app_message.dart';
import '../models/product_model.dart';
import '../core/l10n/app_locale.dart';

class _LineItem {
  String? productId;
  String productName = '';
  String size = '';
  int qty = 1;
  double unitPrice = 0;

  _LineItem();

  double get subtotal => qty * unitPrice;
}

class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({super.key});

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedCustomerId;
  String _customerName = '';
  final _notesCtrl = TextEditingController();
  final List<_LineItem> _items = [_LineItem()];
  bool _loading = false;

  double get _total => _items.fold(0, (sum, i) => sum + i.subtotal);

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      AppMessage.warning(context, ref, 'select_customer');
      return;
    }
    if (_items.any((i) => i.productId == null || i.size.isEmpty)) {
      AppMessage.warning(context, ref, 'complete_line_items');
      return;
    }

    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      final orderData = {
        'customer_id': _selectedCustomerId!,
        'customer_name': _customerName,
        'total': _total,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'created_by': user.id,
      };
      final itemsData = _items
          .map((i) => {
                'product_id': i.productId!,
                'product_name': i.productName,
                'size': i.size,
                'qty': i.qty,
                'unit_price': i.unitPrice,
                'subtotal': i.subtotal,
              })
          .toList();

      await ref
          .read(orderNotifierProvider.notifier)
          .createOrder(orderData, itemsData);
      if (mounted) {
        AppMessage.success(context, ref, 'success_created');
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
    final customers = ref.watch(customersProvider);
    final products = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('new_order', ref))),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    customers.when(
                      data: (list) => DropdownButtonFormField<String>(
                        initialValue: _selectedCustomerId,
                        decoration: InputDecoration(
                            labelText: '${tr('customer', ref)} *'),
                        items: list
                            .map((c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ))
                            .toList(),
                        onChanged: _loading
                            ? null
                            : (v) {
                                final c = list.firstWhere((c) => c.id == v);
                                setState(() {
                                  _selectedCustomerId = v;
                                  _customerName = c.name;
                                });
                              },
                        validator: (v) =>
                            v == null ? tr('required', ref) : null,
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text('${tr('error', ref)}: $e'),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('items', ref),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...List.generate(
                      _items.length,
                      (i) => _LineItemRow(
                        item: _items[i],
                        index: i,
                        products: products.valueOrNull ?? [],
                        onRemove: _items.length > 1
                            ? () => setState(() => _items.removeAt(i))
                            : null,
                        onChanged: () => setState(() {}),
                        enabled: !_loading,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => setState(() => _items.add(_LineItem())),
                      icon: const Icon(Icons.add),
                      label: Text(tr('add_item', ref)),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration:
                          InputDecoration(labelText: tr('notes_optional', ref)),
                      maxLines: 2,
                      enabled: !_loading,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                    top: BorderSide(
                        color: Theme.of(context).colorScheme.outline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('total', ref),
                            style: Theme.of(context).textTheme.labelLarge),
                        Text(
                          AppFormatters.sar(_total),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(tr('place_order', ref)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineItemRow extends ConsumerStatefulWidget {
  final _LineItem item;
  final int index;
  final List<ProductModel> products;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  final bool enabled;

  const _LineItemRow({
    required this.item,
    required this.index,
    required this.products,
    this.onRemove,
    required this.onChanged,
    required this.enabled,
  });

  @override
  ConsumerState<_LineItemRow> createState() => _LineItemRowState();
}

class _LineItemRowState extends ConsumerState<_LineItemRow> {
  final _sizeCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _sizeCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: widget.item.productId,
                    decoration: InputDecoration(
                        labelText: tr('product', ref), isDense: true),
                    items: widget.products
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ))
                        .toList(),
                    onChanged: widget.enabled
                        ? (v) {
                            final p =
                                widget.products.firstWhere((p) => p.id == v);
                            setState(() {
                              widget.item.productId = v;
                              widget.item.productName = p.name;
                              widget.item.unitPrice = p.sellPerPairSar;
                              _priceCtrl.text = p.sellPerPairSar.toString();
                            });
                            widget.onChanged();
                          }
                        : null,
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: widget.enabled ? widget.onRemove : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sizeCtrl,
                    decoration: InputDecoration(
                        labelText: tr('size', ref), isDense: true),
                    validator: AppValidators.required('Size'),
                    onChanged: (v) {
                      widget.item.size = v.trim();
                      widget.onChanged();
                    },
                    enabled: widget.enabled,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: TextFormField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: tr('qty', ref), isDense: true),
                    validator: AppValidators.positiveInt,
                    onChanged: (v) {
                      widget.item.qty = int.tryParse(v) ?? 1;
                      widget.onChanged();
                    },
                    enabled: widget.enabled,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: tr('price', ref), isDense: true),
                    validator: AppValidators.positiveNumber,
                    onChanged: (v) {
                      widget.item.unitPrice = double.tryParse(v) ?? 0;
                      widget.onChanged();
                    },
                    enabled: widget.enabled,
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
