import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/shop_provider.dart';

class ShopFormScreen extends ConsumerStatefulWidget {
  final String? shopId;
  final String? preselectedRouteId;
  const ShopFormScreen({super.key, this.shopId, this.preselectedRouteId});
  @override
  ConsumerState<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends ConsumerState<ShopFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _cityC = TextEditingController();
  String? _routeId;
  int _routeNumber = 0;
  bool _loaded = false;
  bool _saving = false;

  bool get isEdit => widget.shopId != null;

  @override
  void initState() {
    super.initState();
    _routeId = widget.preselectedRouteId;
  }

  @override
  void dispose() {
    _nameC.dispose();
    _phoneC.dispose();
    _cityC.dispose();
    super.dispose();
  }

  void _loadExisting() {
    if (_loaded || !isEdit) return;
    final shop = ref.read(shopDetailProvider(widget.shopId!)).valueOrNull;
    if (shop != null) {
      _nameC.value = TextEditingValue(
          text: shop.name,
          selection: TextSelection.collapsed(offset: shop.name.length));
      final phone = shop.phone ?? '';
      _phoneC.value = TextEditingValue(
          text: phone,
          selection: TextSelection.collapsed(offset: phone.length));
      final city = shop.city ?? '';
      _cityC.value = TextEditingValue(
          text: city, selection: TextSelection.collapsed(offset: city.length));
      _routeId = shop.routeId;
      _routeNumber = shop.routeNumber;
      _loaded = true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_routeId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(warningSnackBar(tr('select_route', ref)));
      return;
    }
    setState(() => _saving = true);
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      final data = {
        'name': _nameC.text.trim(),
        'route_id': _routeId,
        'route_number': _routeNumber,
        'phone': _phoneC.text.trim().isEmpty ? null : _phoneC.text.trim(),
        'city': _cityC.text.trim().isEmpty ? null : _cityC.text.trim(),
      };
      if (isEdit) {
        await ref
            .read(shopNotifierProvider.notifier)
            .updateShop(widget.shopId!, data);
      } else {
        data['created_by'] = user?.id ?? '';
        await ref.read(shopNotifierProvider.notifier).create(data);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(
          errorSnackBar(tr(key, ref)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isEdit) {
      ref.watch(shopDetailProvider(widget.shopId!));
      _loadExisting();
    }
    final user = ref.watch(authUserProvider).valueOrNull;
    final allRoutes = user?.isAdmin == true
        ? ref.watch(routesProvider).valueOrNull ?? []
        : ref.watch(routesBySellerProvider(user?.id ?? '')).valueOrNull ?? [];
    final routes = user?.isAdmin == true
        ? allRoutes
        : allRoutes.where((r) => r.id == user?.assignedRouteId).toList();

    if (_routeId == null &&
        user?.isSeller == true &&
        user?.assignedRouteId != null) {
      final assigned =
          routes.where((r) => r.id == user!.assignedRouteId).firstOrNull;
      if (assigned != null) {
        _routeId = assigned.id;
        _routeNumber = assigned.routeNumber;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? tr('edit_shop', ref) : tr('new_shop', ref)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _routeId,
                decoration: InputDecoration(labelText: '${tr('route', ref)} *'),
                items: routes
                    .map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('R${r.routeNumber} - ${r.name}'),
                        ))
                    .toList(),
                validator: (v) => v == null ? tr('required', ref) : null,
                onChanged: user?.isAdmin == true
                    ? (v) {
                        final r = routes.where((r) => r.id == v).firstOrNull;
                        setState(() {
                          _routeId = v;
                          _routeNumber = r?.routeNumber ?? 0;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameC,
                decoration:
                    InputDecoration(labelText: '${tr('shop_name', ref)} *'),
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
