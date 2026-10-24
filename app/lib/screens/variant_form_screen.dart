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
import '../widgets/error_state.dart';

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

  void _loadExisting(ProductVariantModel variant) {
    if (_loaded || !isEdit || variant.id != widget.variantId) return;
    _variantNameC.value = TextEditingValue(
      text: variant.variantName,
      selection: TextSelection.collapsed(offset: variant.variantName.length),
    );
    _loaded = true;
  }

  Future<void> _save() async {
    if (_saving || (isEdit && !_loaded)) return;
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }

    setState(() => _saving = true);
    bool saved = false;
    try {
      final user = await ref.read(authUserProvider.future);
      if (user?.isAdmin != true) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(tr('permission_denied', ref)));
        }
        return;
      }

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
    final userAsync = ref.watch(authUserProvider);
    if (userAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (userAsync.hasError) {
      return Scaffold(
        body: mappedErrorState(
          error: userAsync.error!,
          ref: ref,
          onRetry: () => ref.invalidate(authUserProvider),
        ),
      );
    }
    if (userAsync.value?.isAdmin != true) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }

    final variantsAsync = ref.watch(productVariantsProvider(widget.productId));
    if (isEdit) {
      if (variantsAsync.hasError) {
        return Scaffold(
          body: mappedErrorState(
            error: variantsAsync.error!,
            ref: ref,
            onRetry: () =>
                ref.invalidate(productVariantsProvider(widget.productId)),
          ),
        );
      }
      if (variantsAsync.isLoading && !variantsAsync.hasValue) {
        return const Scaffold(body: LinearProgressIndicator());
      }
      final variant = variantsAsync.value
          ?.where((candidate) => candidate.id == widget.variantId)
          .firstOrNull;
      if (variant == null || variant.id != widget.variantId) {
        return Scaffold(
          body: ErrorState(
            message: tr('err_not_found', ref),
            onRetry: () =>
                ref.invalidate(productVariantsProvider(widget.productId)),
            retryLabel: tr('retry', ref),
          ),
        );
      }
      _loadExisting(variant);
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
                      onPressed: _saving || (isEdit && !_loaded) ? null : _save,
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
