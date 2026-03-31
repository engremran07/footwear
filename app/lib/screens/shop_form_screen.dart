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
import '../providers/auth_provider.dart';
import '../providers/route_provider.dart';
import '../providers/shop_provider.dart';
import '../widgets/confirm_dialog.dart';

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
  bool _isDirty = false;

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
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }
    if (_routeId == null) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context)
          .showSnackBar(warningSnackBar(tr('select_route', ref)));
      return;
    }
    setState(() => _saving = true);
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      final data = {
        'name': AppSanitizer.name(_nameC.text),
        'route_id': _routeId,
        'route_number': _routeNumber,
        'phone': _phoneC.text.trim().isEmpty
            ? null
            : AppSanitizer.phone(_phoneC.text),
        'city': _cityC.text.trim().isEmpty
            ? null
            : AppSanitizer.text(_cityC.text, maxLength: 100),
      };
      if (isEdit) {
        await ref
            .read(shopNotifierProvider.notifier)
            .updateShop(widget.shopId!, data);
      } else {
        data['created_by'] = user?.id ?? '';
        await ref.read(shopNotifierProvider.notifier).create(data);
      }
      if (mounted) {
        HapticFeedback.mediumImpact();
        _isDirty = false;
        context.pop();
      }
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
            title: Text(isEdit ? tr('edit_shop', ref) : tr('new_shop', ref)),
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
                  DropdownButtonFormField<String>(
                    initialValue: _routeId,
                    decoration:
                        InputDecoration(labelText: '${tr('route', ref)} *'),
                    items: routes
                        .map((r) => DropdownMenuItem(
                              value: r.id,
                              child: Text('R${r.routeNumber} - ${r.name}'),
                            ))
                        .toList(),
                    validator: (v) => v == null ? tr('required', ref) : null,
                    onChanged: user?.isAdmin == true
                        ? (v) {
                            final r =
                                routes.where((r) => r.id == v).firstOrNull;
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
