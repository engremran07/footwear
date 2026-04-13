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
import '../providers/user_provider.dart';
import '../widgets/confirm_dialog.dart';

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
  bool _isDirty = false;

  bool get isEdit => widget.routeId != null;

  @override
  void dispose() {
    _nameC.dispose();
    super.dispose();
  }

  void _loadExisting() {
    if (_loaded || !isEdit) return;
    final detail = ref.read(routeDetailProvider(widget.routeId!)).value;
    if (detail != null) {
      _nameC.value = TextEditingValue(
        text: detail.name,
        selection: TextSelection.collapsed(offset: detail.name.length),
      );
      _sellerId = detail.assignedSellerId;
      _sellerName = detail.assignedSellerName;
      _loaded = true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.vibrate();
      return;
    }
    setState(() => _saving = true);
    bool saved = false;
    try {
      final user = ref.read(authUserProvider).value;
      final Map<String, dynamic> data = {
        'name': AppSanitizer.name(_nameC.text),
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
      saved = true;
    } catch (e) {
      if (mounted) {
        final key = AppErrorMapper.key(e);
        ScaffoldMessenger.of(context).showSnackBar(errorSnackBar(tr(key, ref)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // context.pop() is OUTSIDE the try-catch so a navigation exception
    // cannot trigger the error SnackBar after a successful save.
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
      ref.watch(routeDetailProvider(widget.routeId!));
      _loadExisting();
    }
    final user = ref.watch(authUserProvider).value;
    final isAdmin = user?.isAdmin ?? false;

    if (!isAdmin) {
      return Scaffold(body: Center(child: Text(tr('permission_denied', ref))));
    }

    // BUG-002 FIX-A: use sellersProvider (role == 'seller') so admins never
    // appear in the route seller dropdown — assigning an admin to a route
    // would incorrectly write assigned_route_id to the admin user doc,
    // breaking their god-mode and Firestore rule admin path.
    final sellers = ref.watch(sellersProvider).value ?? [];

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await ConfirmDialog.show(
          context,
          title: tr('unsaved_changes', ref),
          message: tr('discard_changes_prompt', ref),
          confirmLabel: tr('discard', ref),
          isDestructive: true,
        );
        if (discard && context.mounted) context.pop();
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
                  TextFormField(
                    controller: _nameC,
                    decoration: InputDecoration(
                      labelText: '${tr('route_name', ref)} *',
                    ),
                    validator: (v) => Validators.notEmpty(v),
                    autofocus: !isEdit,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    inputFormatters: [AppInputFormatters.maxLength(200)],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _sellerId,
                    decoration: InputDecoration(
                      labelText: tr('assigned_seller', ref),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(tr('none', ref)),
                      ),
                      ...sellers.map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.displayName),
                        ),
                      ),
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
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
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
