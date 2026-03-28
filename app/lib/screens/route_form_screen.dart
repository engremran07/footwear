import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/user_provider.dart';

class RouteFormScreen extends ConsumerStatefulWidget {
  final String? routeId;
  const RouteFormScreen({super.key, this.routeId});
  @override
  ConsumerState<RouteFormScreen> createState() => _RouteFormScreenState();
}

class _RouteFormScreenState extends ConsumerState<RouteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  String? _sellerId;
  String? _sellerName;
  bool _loaded = false;
  bool _saving = false;

  bool get isEdit => widget.routeId != null;

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  void _loadExisting() {
    if (_loaded || !isEdit) return;
    final detail = ref.read(routeDetailProvider(widget.routeId!)).valueOrNull;
    if (detail != null) {
      _nameC.value = TextEditingValue(
          text: detail.name,
          selection: TextSelection.collapsed(offset: detail.name.length));
      _sellerId = detail.assignedSellerId;
      _sellerName = detail.assignedSellerName;
      _loaded = true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      final Map<String, dynamic> data = {
        'name': _nameC.text.trim(),
        'assigned_seller_id': _sellerId,
        'assigned_seller_name': _sellerName,
      };
      if (isEdit) {
        await ref
            .read(routeNotifierProvider.notifier)
            .updateRoute(widget.routeId!, data);
      } else {
        data['created_by'] = user?.id ?? '';
        await ref.read(routeNotifierProvider.notifier).create(data);
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
    if (isEdit) {
      ref.watch(routeDetailProvider(widget.routeId!));
      _loadExisting();
    }
    final sellers = ref.watch(sellersProvider).valueOrNull ?? [];
    final user = ref.watch(authUserProvider).valueOrNull;
    final isAdmin = user?.isAdmin ?? false;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('routes', ref))),
        body: Center(child: Text(tr('permission_denied', ref))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? tr('edit_route', ref) : tr('new_route', ref)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameC,
                decoration:
                    InputDecoration(labelText: '${tr('route_name', ref)} *'),
                validator: (v) => Validators.notEmpty(v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _sellerId,
                decoration:
                    InputDecoration(labelText: tr('assigned_seller', ref)),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text(tr('none', ref)),
                  ),
                  ...sellers.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.displayName),
                      )),
                ],
                onChanged: (v) {
                  setState(() {
                    _sellerId = v;
                    _sellerName = sellers
                        .where((s) => s.id == v)
                        .map((s) => s.displayName)
                        .firstOrNull;
                  });
                },
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
