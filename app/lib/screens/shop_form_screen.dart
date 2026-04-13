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
  bool _routeAutoAssigned = false;

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
    final shop = ref.read(shopDetailProvider(widget.shopId!)).value;
    if (shop != null) {
      _nameC.value = TextEditingValue(
        text: shop.name,
        selection: TextSelection.collapsed(offset: shop.name.length),
      );
      final phone = shop.phone ?? '';
      _phoneC.value = TextEditingValue(
        text: phone,
        selection: TextSelection.collapsed(offset: phone.length),
      );
      final city = shop.city ?? '';
      _cityC.value = TextEditingValue(
        text: city,
        selection: TextSelection.collapsed(offset: city.length),
      );
      _routeId = shop.routeId;
      _routeNumber = shop.routeNumber;
      _loaded = true;
    }
  }

  Future<void> _save() async {
    if (_saving) return; // synchronous guard — prevents double-submit race
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }
    if (_routeId == null) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('select_route', ref)));
      return;
    }
    setState(() => _saving = true);
    bool saved = false;
    try {
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
        // created_by is set by the provider from Firebase Auth uid directly.
        await ref.read(shopNotifierProvider.notifier).create(data);
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
    if (isEdit) {
      ref.watch(shopDetailProvider(widget.shopId!));
      _loadExisting();
    }
    final user = ref.watch(authUserProvider).value;
    final routesAsync = user?.isAdmin == true
        ? ref.watch(routesProvider)
        : ref.watch(routesBySellerProvider(user?.id ?? ''));
    final routesLoading = user != null && routesAsync.isLoading;
    final allRoutes = routesAsync.value ?? [];
    final routes = user?.isAdmin == true
        ? allRoutes
        : allRoutes.where((r) => r.id == user?.assignedRouteId).toList();

    // Seller: set route directly from user profile without waiting for routes to load.
    // Guard with !isEdit so edit-mode shops keep their stored route_id.
    if (!_routeAutoAssigned &&
        _routeId == null &&
        !isEdit &&
        user?.isSeller == true &&
        user?.assignedRouteId != null) {
      _routeAutoAssigned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _routeId = user!.assignedRouteId);
      });
    }
    // Sync routeNumber once route list loads (works for both admin and seller).
    if (_routeId != null && _routeNumber == 0) {
      final r = allRoutes.where((r) => r.id == _routeId).firstOrNull;
      if (r != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _routeNumber = r.routeNumber);
        });
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
                    key: ValueKey(_routeId),
                    initialValue: _routeId,
                    decoration: InputDecoration(
                      labelText: '${tr('route', ref)} *',
                      suffixIcon: routesLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    // When _routeId is set but the list hasn't loaded yet (e.g. seller
                    // offline / slow connection), provide a placeholder item so that
                    // Flutter's assertion (value must be in items) does not fire.
                    items: routes.isNotEmpty
                        ? routes
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r.id,
                                  child: Text('${r.routeNumber} - ${r.name}'),
                                ),
                              )
                              .toList()
                        : (_routeId != null
                              ? [
                                  DropdownMenuItem(
                                    value: _routeId,
                                    child: Text(
                                      routesLoading
                                          ? tr('loading', ref)
                                          : _routeId!,
                                    ),
                                  ),
                                ]
                              : []),
                    validator: (v) => v == null ? tr('required', ref) : null,
                    onChanged: user?.isAdmin == true
                        ? routesLoading
                              ? null
                              : (v) {
                                  final r = routes
                                      .where((r) => r.id == v)
                                      .firstOrNull;
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
                    decoration: InputDecoration(
                      labelText: '${tr('shop_name', ref)} *',
                    ),
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
                      onPressed:
                          _saving ||
                              (routesLoading &&
                                  user.isAdmin &&
                                  _routeId == null)
                          ? null
                          : _save,
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
