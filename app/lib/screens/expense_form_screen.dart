import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../providers/expense_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../models/settings_model.dart';
import '../core/utils/validators.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'other';
  String? _receiptUrl;
  bool _loading = false;

  List<String> get _categories {
    final s = ref.watch(settingsProvider).valueOrNull;
    return s?.expenseCategories ?? SettingsModel.defaultExpenseCategories;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _loading = true);
    try {
      final id = const Uuid().v4();
      final bytes = await picked.readAsBytes();
      final url = await ref
          .read(expenseNotifierProvider.notifier)
          .uploadReceipt(id, bytes);
      setState(() => _receiptUrl = url);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      await ref.read(expenseNotifierProvider.notifier).create(
        {
          'category': _category,
          'amount': double.parse(_amountCtrl.text.trim()),
          'description': _descCtrl.text.trim(),
          if (_receiptUrl != null) 'receipt_url': _receiptUrl,
        },
        user.id,
      );
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
    return Scaffold(
      appBar: AppBar(title: Text(tr('new_expense', ref))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration:
                    InputDecoration(labelText: '${tr('category', ref)} *'),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.toUpperCase()),
                        ))
                    .toList(),
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: '${tr('amount_sar', ref)} *'),
                validator: AppValidators.positiveNumber,
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration:
                    InputDecoration(labelText: '${tr('description', ref)} *'),
                validator: AppValidators.required('Description'),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _receiptUrl != null
                        ? Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green),
                              const SizedBox(width: 8),
                              Text(tr('receipt_attached', ref)),
                            ],
                          )
                        : Text(tr('no_receipt', ref)),
                  ),
                  TextButton.icon(
                    onPressed: _loading ? null : _pickReceipt,
                    icon: const Icon(Icons.attach_file),
                    label: Text(tr('attach_receipt', ref)),
                  ),
                ],
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
                      : Text(tr('submit_approval', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
