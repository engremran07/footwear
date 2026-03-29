import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';

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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      final data = <String, dynamic>{
        'name': _nameC.text.trim(),
        'phone': _phoneC.text.trim().isEmpty ? null : _phoneC.text.trim(),
        'city': _cityC.text.trim().isEmpty ? null : _cityC.text.trim(),
      };
      if (isEdit) {
        await ref
            .read(customerNotifierProvider.notifier)
            .updateCustomer(widget.customerId!, data);
      } else {
        data['created_by'] = user?.id ?? '';
        await ref.read(customerNotifierProvider.notifier).create(data);
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
      ref.watch(customerDetailProvider(widget.customerId!));
      _loadExisting();
    }

    return Scaffold(
      appBar: AppBar(
        title:
            Text(isEdit ? tr('edit_customer', ref) : tr('new_customer', ref)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameC,
                decoration: InputDecoration(labelText: '${tr('name', ref)} *'),
                validator: (v) => Validators.notEmpty(v),
                autofocus: !isEdit,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneC,
                decoration: InputDecoration(labelText: tr('phone', ref)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cityC,
                decoration: InputDecoration(labelText: tr('city', ref)),
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
