import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/validators.dart';
import '../models/product_variant_model.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';

class VariantFormScreen extends ConsumerStatefulWidget {
  final String productId;
  final String? variantId;
  const VariantFormScreen({super.key, required this.productId, this.variantId});
  @override
  ConsumerState<VariantFormScreen> createState() => _VariantFormScreenState();
}

class _VariantFormScreenState extends ConsumerState<VariantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _variantNameC = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  bool get isEdit => widget.variantId != null;

  @override
  void dispose() {
    _variantNameC.dispose();
    super.dispose();
  }

  void _loadExisting(List<ProductVariantModel> variants) {
    if (_loaded || !isEdit) return;
    final v = variants.where((v) => v.id == widget.variantId).firstOrNull;
    if (v != null) {
      _variantNameC.value = TextEditingValue(
          text: v.variantName,
          selection: TextSelection.collapsed(offset: v.variantName.length));
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
        'product_id': widget.productId,
        'variant_name': _variantNameC.text.trim(),
        'quantity_available':
            0, // New variants start with 0; admin adds stock later
      };
      final notifier = ref.read(productNotifierProvider.notifier);
      if (isEdit) {
        await notifier.updateVariant(widget.variantId!, data);
      } else {
        await notifier.createVariant(data);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(key, ref))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final variantsAsync = ref.watch(productVariantsProvider(widget.productId));
    if (isEdit) {
      variantsAsync.whenData((vars) => _loadExisting(vars));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? tr('edit_variant', ref) : tr('new_variant', ref)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _variantNameC,
                decoration: InputDecoration(
                  labelText: '${tr('variant_name', ref)} *',
                  hintText: 'e.g., Black • Size 40',
                ),
                validator: (v) => Validators.notEmpty(v),
                autofocus: !isEdit,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(tr('saving', ref)),
                          ],
                        )
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
