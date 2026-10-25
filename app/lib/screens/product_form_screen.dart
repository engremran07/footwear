import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/product_model.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_sanitizer.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/input_formatters.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/error_state.dart';

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
  bool _isDirty = false;

  bool get isEdit => widget.productId != null;

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  void _loadExisting(ProductModel product) {
    if (_loaded || !isEdit || product.id != widget.productId) return;
    _nameC.value = TextEditingValue(
      text: product.name,
      selection: TextSelection.collapsed(offset: product.name.length),
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
      if (user?.canManageOperationalData != true) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(tr('permission_denied', ref)));
        }
        return;
      }

      final data = {'name': AppSanitizer.name(_nameC.text)};
      final notifier = ref.read(productNotifierProvider.notifier);
      if (isEdit) {
        await notifier.updateProduct(widget.productId!, data);
      } else {
        await notifier.createProduct(data);
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
    if (userAsync.value?.canManageOperationalData != true) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }

    if (isEdit) {
      final productAsync = ref.watch(productDetailProvider(widget.productId!));
      if (productAsync.hasError) {
        return Scaffold(
          body: mappedErrorState(
            error: productAsync.error!,
            ref: ref,
            onRetry: () =>
                ref.invalidate(productDetailProvider(widget.productId!)),
          ),
        );
      }
      if (productAsync.isLoading && !productAsync.hasValue) {
        return const Scaffold(body: LinearProgressIndicator());
      }
      final product = productAsync.value;
      if (product == null || product.id != widget.productId) {
        return Scaffold(
          body: ErrorState(
            message: tr('err_not_found', ref),
            onRetry: () =>
                ref.invalidate(productDetailProvider(widget.productId!)),
            retryLabel: tr('retry', ref),
          ),
        );
      }
      _loadExisting(product);
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
                    controller: _nameC,
                    decoration: InputDecoration(
                      labelText: '${tr('product_name', ref)} *',
                    ),
                    validator: (v) => Validators.notEmpty(v),
                    autofocus: !isEdit,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    inputFormatters: [AppInputFormatters.maxLength(200)],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving || (isEdit && !_loaded) ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
