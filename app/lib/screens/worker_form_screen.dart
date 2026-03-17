import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/worker_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../core/utils/validators.dart';
import '../core/utils/app_message.dart';
import '../core/l10n/app_locale.dart';

class WorkerFormScreen extends ConsumerStatefulWidget {
  final String? workerId;
  const WorkerFormScreen({super.key, this.workerId});

  @override
  ConsumerState<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends ConsumerState<WorkerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  String _type = 'pk';
  bool _loading = false;

  bool get _isEdit => widget.workerId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  void _load() {
    final w = ref.read(workerDetailProvider(widget.workerId!)).valueOrNull;
    if (w != null) {
      _nameCtrl.text = w.name;
      _rateCtrl.text = w.ratePerPair.toString();
      setState(() => _type = w.type);
    } else {
      _prefillRate();
    }
  }

  void _prefillRate() {
    if (_rateCtrl.text.isNotEmpty) return;
    final s = ref.read(settingsProvider).valueOrNull;
    if (s == null) return;
    _rateCtrl.text =
        (_type == 'pk' ? s.defaultPkRate : s.defaultKsaRate).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'type': _type,
        'rate_per_pair': double.parse(_rateCtrl.text.trim()),
        'currency': _type == 'pk' ? 'PKR' : 'SAR',
        'joined_at': Timestamp.now(),
      };
      final notifier = ref.read(workerNotifierProvider.notifier);
      if (_isEdit) {
        await notifier.save(widget.workerId!, data);
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
    if (user == null || !user.isAdmin) {
      return Scaffold(body: Center(child: Text(tr('access_denied', ref))));
    }
    return Scaffold(
      appBar: AppBar(
          title:
              Text(_isEdit ? tr('edit_worker', ref) : tr('new_worker', ref))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: '${tr('name', ref)} *'),
                validator: AppValidators.required('Name'),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration:
                    InputDecoration(labelText: '${tr('type_label', ref)} *'),
                items: [
                  DropdownMenuItem(
                      value: 'pk', child: Text(tr('pakistan_pk', ref))),
                  DropdownMenuItem(
                      value: 'ksa', child: Text(tr('saudi_ksa', ref))),
                ],
                onChanged: _loading
                    ? null
                    : (v) {
                        setState(() => _type = v ?? 'pk');
                        _prefillRate();
                      },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${tr('rate_per_pair', ref)} *',
                  suffixText: _type == 'pk' ? 'PKR' : 'SAR',
                ),
                validator: AppValidators.positiveNumber,
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
                          ? tr('update_worker', ref)
                          : tr('add_worker', ref)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
