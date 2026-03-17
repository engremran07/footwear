import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/supplier_provider.dart';
import '../models/supplier_model.dart';
import '../core/utils/validators.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  final String? supplierId;
  const SupplierFormScreen({super.key, this.supplierId});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _paymentTermsCtrl = TextEditingController();
  bool _saving = false;
  bool _initialized = false;

  bool get _isEdit => widget.supplierId != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _paymentTermsCtrl.dispose();
    super.dispose();
  }

  void _initFrom(SupplierModel s) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = s.name;
    _contactCtrl.text = s.contactName;
    _phoneCtrl.text = s.phone;
    _emailCtrl.text = s.email ?? '';
    _addressCtrl.text = s.address ?? '';
    _paymentTermsCtrl.text = s.paymentTerms;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'contact_name': _contactCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'address':
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'payment_terms': _paymentTermsCtrl.text.trim(),
        'active': true,
      };
      if (_isEdit) {
        await ref
            .read(supplierNotifierProvider.notifier)
            .save(widget.supplierId!, data);
      } else {
        await ref.read(supplierNotifierProvider.notifier).create(data);
      }
      if (mounted) {
        AppMessage.success(
            context, ref, _isEdit ? 'success_updated' : 'success_created');
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
    if (_isEdit) {
      final supplierAsync =
          ref.watch(supplierDetailProvider(widget.supplierId!));
      supplierAsync.whenData((s) {
        if (s != null) _initFrom(s);
      });
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(
              _isEdit ? tr('edit_supplier', ref) : tr('new_supplier', ref))),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                  labelText: '${tr('company_name', ref)} *',
                  border: const OutlineInputBorder()),
              validator: Validators.notEmpty,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactCtrl,
              decoration: InputDecoration(
                  labelText: '${tr('contact_person', ref)} *',
                  border: const OutlineInputBorder()),
              validator: Validators.notEmpty,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: InputDecoration(
                  labelText: '${tr('phone', ref)} *',
                  border: const OutlineInputBorder()),
              keyboardType: TextInputType.phone,
              validator: Validators.notEmpty,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                  labelText: tr('email', ref),
                  border: const OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
              validator: Validators.optionalEmail,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressCtrl,
              decoration: InputDecoration(
                  labelText: tr('address', ref),
                  border: const OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _paymentTermsCtrl,
              decoration: InputDecoration(
                  labelText: '${tr('payment_terms', ref)} *',
                  hintText: tr('payment_terms_hint', ref),
                  border: const OutlineInputBorder()),
              validator: Validators.notEmpty,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEdit
                      ? tr('save_changes', ref)
                      : tr('create_supplier', ref)),
            ),
          ],
        ),
      ),
    );
  }
}
