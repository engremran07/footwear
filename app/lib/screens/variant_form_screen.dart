import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_sanitizer.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/input_formatters.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/validators.dart';
import '../models/product_variant_model.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/confirm_dialog.dart';

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
  bool _isDirty = false;

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
        selection: TextSelection.collapsed(offset: v.variantName.length),
      );
      _loaded = true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    final user = ref.read(authUserProvider).value;
    if (user?.isAdmin != true) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr('permission_denied', ref)));
      }
      return;
    }

    setState(() => _saving = true);
    bool saved = false;
    try {
      final data = {
        'product_id': widget.productId,
        'variant_name': AppSanitizer.name(_variantNameC.text),
        'quantity_available':
            0, // New variants start with 0; admin adds stock later
      };
      final notifier = ref.read(productNotifierProvider.notifier);
      if (isEdit) {
        await notifier.updateVariant(widget.variantId!, data);
      } else {
        await notifier.createVariant(data);
      }
      saved = true;
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (saved && mounted) {
      HapticFeedback.mediumImpact();
      _isDirty = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('saved_successfully', ref)));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final variantsAsync = ref.watch(productVariantsProvider(widget.productId));
    if (isEdit) {
      variantsAsync.whenData((vars) => _loadExisting(vars));
    }

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await ConfirmDialog.show(
          context,
          title: tr('unsaved_changes', ref),
          message: tr('discard_changes_prompt', ref),
          confirmLabel: tr('discard', ref),
          isDestructive: true,
        );
        if (discard && context.mounted) context.pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              onChanged: () {
                if (!_isDirty) setState(() => _isDirty = true);
              },
              child: Column(
                children: [
                  TextFormField(
                    controller: _variantNameC,
                    decoration: InputDecoration(
                      labelText: '${tr('variant_name', ref)} *',
                      hintText: tr('hint_variant_example', ref),
                    ),
                    validator: (v) => Validators.notEmpty(v),
                    autofocus: !isEdit,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    inputFormatters: [AppInputFormatters.maxLength(200)],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
        ),
      ),
    );
  }
}
