import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final String? productId;
  const ProductFormScreen({super.key, this.productId});
  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  bool get isEdit => widget.productId != null;

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  void _loadExisting() {
    if (_loaded || !isEdit) return;
    final p = ref.read(productDetailProvider(widget.productId!)).valueOrNull;
    if (p != null) {
      _nameC.value = TextEditingValue(
          text: p.name,
          selection: TextSelection.collapsed(offset: p.name.length));
      _loaded = true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(authUserProvider).valueOrNull;
    if (user?.isAdmin != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('permission_denied', ref))),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'name': _nameC.text.trim(),
      };
      final notifier = ref.read(productNotifierProvider.notifier);
      if (isEdit) {
        await notifier.updateProduct(widget.productId!, data);
      } else {
        await notifier.createProduct(data);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isEdit) {
      ref.watch(productDetailProvider(widget.productId!));
      _loadExisting();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? tr('edit_product', ref) : tr('new_product', ref)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameC,
                decoration:
                    InputDecoration(labelText: '${tr('product_name', ref)} *'),
                validator: (v) => Validators.notEmpty(v),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(tr('save', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
