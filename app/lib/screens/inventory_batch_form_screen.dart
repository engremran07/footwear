import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/inventory_provider.dart';
import '../providers/product_provider.dart';
import '../providers/worker_provider.dart';
import '../providers/auth_provider.dart';
import '../core/utils/validators.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class InventoryBatchFormScreen extends ConsumerStatefulWidget {
  const InventoryBatchFormScreen({super.key});

  @override
  ConsumerState<InventoryBatchFormScreen> createState() =>
      _InventoryBatchFormScreenState();
}

class _InventoryBatchFormScreenState
    extends ConsumerState<InventoryBatchFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  String? _selectedProductId;
  String? _selectedWorkerId;
  bool _loading = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProductId == null) {
      AppMessage.warning(context, ref, 'select_product');
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(inventoryBatchNotifierProvider.notifier).create({
        'product_id': _selectedProductId!,
        'qty_produced': int.parse(_qtyCtrl.text.trim()),
        'cost_total': double.parse(_costCtrl.text.trim()),
        'source': 'production',
        if (_selectedWorkerId != null) 'worker_id': _selectedWorkerId,
      });
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
    final products = ref.watch(productsProvider);
    final workers = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('new_batch', ref))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              products.when(
                data: (list) => DropdownButtonFormField<String>(
                  initialValue: _selectedProductId,
                  decoration:
                      InputDecoration(labelText: '${tr('product', ref)} *'),
                  items: list
                      .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _selectedProductId = v),
                  validator: (v) =>
                      v == null ? tr('required_field', ref) : null,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('${tr('error', ref)}: $e'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: '${tr('qty_produced', ref)} *'),
                validator: AppValidators.positiveInt,
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: '${tr('total_cost', ref)} (SAR) *'),
                validator: AppValidators.positiveNumber,
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              workers.when(
                data: (list) => DropdownButtonFormField<String>(
                  initialValue: _selectedWorkerId,
                  decoration:
                      InputDecoration(labelText: tr('assign_worker', ref)),
                  items: [
                    DropdownMenuItem(
                        value: null, child: Text(tr('no_worker', ref))),
                    ...list
                        .where((w) => w.type == 'pk')
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            )),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _selectedWorkerId = v),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
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
                      : Text(tr('create_batch', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
