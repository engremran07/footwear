import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/app_sanitizer.dart';
import '../core/utils/input_formatters.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../widgets/confirm_dialog.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? customerId;
  const CustomerFormScreen({super.key, this.customerId});
  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _cityC = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  bool _isDirty = false;

  bool get isEdit => widget.customerId != null;

  @override
  void dispose() {
    _nameC.dispose();
    _phoneC.dispose();
    _cityC.dispose();
    super.dispose();
  }

  void _loadExisting() {
    if (_loaded || !isEdit) return;
    final detail =
        ref.read(customerDetailProvider(widget.customerId!)).valueOrNull;
    if (detail != null) {
      _nameC.value = TextEditingValue(
          text: detail.name,
          selection: TextSelection.collapsed(offset: detail.name.length));
      final phone = detail.phone ?? '';
      _phoneC.value = TextEditingValue(
          text: phone,
          selection: TextSelection.collapsed(offset: phone.length));
      final city = detail.city ?? '';
      _cityC.value = TextEditingValue(
          text: city, selection: TextSelection.collapsed(offset: city.length));
      _loaded = true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }
    setState(() => _saving = true);
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      final data = <String, dynamic>{
        'name': AppSanitizer.name(_nameC.text),
        'phone': _phoneC.text.trim().isEmpty
            ? null
            : AppSanitizer.phone(_phoneC.text),
        'city': _cityC.text.trim().isEmpty
            ? null
            : AppSanitizer.text(_cityC.text, maxLength: 100),
      };
      if (isEdit) {
        await ref
            .read(customerNotifierProvider.notifier)
            .updateCustomer(widget.customerId!, data);
      } else {
        data['created_by'] = user?.id ?? '';
        await ref.read(customerNotifierProvider.notifier).create(data);
      }
      if (mounted) {
        HapticFeedback.mediumImpact();
        _isDirty = false;
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar('$e'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isEdit) {
      ref.watch(customerDetailProvider(widget.customerId!));
      _loadExisting();
    }

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await ConfirmDialog.show(
          context,
          title: tr('unsaved_changes', ref),
          message: tr('discard_changes_message', ref),
        );
        if (leave == true && context.mounted) context.pop();
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Text(
                isEdit ? tr('edit_customer', ref) : tr('new_customer', ref)),
          ),
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
                    decoration:
                        InputDecoration(labelText: '${tr('name', ref)} *'),
                    validator: (v) => Validators.notEmpty(v),
                    inputFormatters: [AppInputFormatters.maxLength(200)],
                    textInputAction: TextInputAction.next,
                    autofocus: !isEdit,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneC,
                    decoration: InputDecoration(labelText: tr('phone', ref)),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      AppInputFormatters.phoneFormatter,
                      AppInputFormatters.maxLength(20),
                    ],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cityC,
                    decoration: InputDecoration(labelText: tr('city', ref)),
                    inputFormatters: [AppInputFormatters.maxLength(100)],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
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
        ),
      ),
    );
  }
}
