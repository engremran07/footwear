import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/customer_provider.dart';
import '../providers/auth_provider.dart';
import '../models/customer_model.dart';
import '../core/utils/validators.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? customerId;
  const CustomerFormScreen({super.key, this.customerId});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: 'Saudi Arabia');
  final _areaCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type = 'individual';
  bool _loading = false;

  bool get _isEdit => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomer());
    }
  }

  void _loadCustomer() {
    final c = ref.read(customerDetailProvider(widget.customerId!)).valueOrNull;
    if (c != null) _populate(c);
  }

  void _populate(CustomerModel c) {
    _nameCtrl.text = c.name;
    _phoneCtrl.text = c.phone;
    _emailCtrl.text = c.email ?? '';
    _addressCtrl.text = c.address ?? '';
    _cityCtrl.text = c.city ?? '';
    _countryCtrl.text = c.country;
    _areaCtrl.text = c.area ?? '';
    _contactNameCtrl.text = c.contactName ?? '';
    _notesCtrl.text = c.notes ?? '';
    _type = c.type;
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _areaCtrl.dispose();
    _contactNameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'type': _type,
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_addressCtrl.text.trim().isNotEmpty)
          'address': _addressCtrl.text.trim(),
        if (_cityCtrl.text.trim().isNotEmpty) 'city': _cityCtrl.text.trim(),
        'country': _countryCtrl.text.trim(),
        if (_areaCtrl.text.trim().isNotEmpty) 'area': _areaCtrl.text.trim(),
        if (_contactNameCtrl.text.trim().isNotEmpty)
          'contact_name': _contactNameCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      };
      final notifier = ref.read(customerNotifierProvider.notifier);
      if (_isEdit) {
        await notifier.save(widget.customerId!, data);
      } else {
        await notifier.create(data);
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null || !user.canWrite) {
      return Scaffold(body: Center(child: Text(tr('access_denied', ref))));
    }
    return Scaffold(
      appBar: AppBar(
          title: Text(
              _isEdit ? tr('edit_customer', ref) : tr('new_customer', ref))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                    labelText: '${tr('type', ref)} *',
                    border: const OutlineInputBorder()),
                initialValue: _type,
                items: const [
                  DropdownMenuItem(
                      value: 'individual', child: Text('Individual')),
                  DropdownMenuItem(value: 'shop', child: Text('Shop')),
                  DropdownMenuItem(
                      value: 'wholesale', child: Text('Wholesale')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: '${tr('name', ref)} *'),
                validator: AppValidators.required('Name'),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: '${tr('phone', ref)} *'),
                validator: AppValidators.phone,
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    InputDecoration(labelText: tr('email_optional', ref)),
                validator: (v) =>
                    v == null || v.isEmpty ? null : AppValidators.email(v),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration:
                    InputDecoration(labelText: tr('address_optional', ref)),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cityCtrl,
                decoration:
                    InputDecoration(labelText: tr('city_optional', ref)),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _countryCtrl,
                decoration:
                    InputDecoration(labelText: '${tr('country', ref)} *'),
                validator: AppValidators.required('Country'),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _areaCtrl,
                decoration:
                    InputDecoration(labelText: tr('area', ref)),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactNameCtrl,
                decoration:
                    InputDecoration(labelText: tr('contact_name', ref)),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration:
                    InputDecoration(labelText: tr('notes', ref)),
                maxLines: 3,
                enabled: !_loading,
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
                      : Text(_isEdit
                          ? tr('update_customer', ref)
                          : tr('add_customer', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
