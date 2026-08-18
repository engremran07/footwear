import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/l10n/app_locale.dart';
import '../core/theme/app_fonts.dart';
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
  final List<String> _selectedSellerIds = [];
  final List<String> _selectedSellerNames = [];
  String _currency = 'SAR';
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
      _selectedSellerIds
        ..clear()
        ..addAll(detail.assignedSellerIds);
      _selectedSellerNames
        ..clear()
        ..addAll(detail.assignedSellerNames);
      _currency = detail.currency;
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
      final user = await ref.read(authUserProvider.future);
      final createdBy = user?.id.trim() ?? '';
      final Map<String, dynamic> data = {
        'name': AppSanitizer.name(_nameC.text),
        'assigned_seller_ids': List<String>.from(_selectedSellerIds),
        'assigned_seller_names': List<String>.from(_selectedSellerNames),
        'currency': _currency,
      };
      if (isEdit) {
        await ref
            .read(routeNotifierProvider.notifier)
            .updateRoute(widget.routeId!, data);
      } else {
        if (createdBy.isEmpty) {
          throw StateError('createdBy must not be empty');
        }
        data['created_by'] = createdBy;
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
    if (saved && mounted) {
      HapticFeedback.mediumImpact();
      _isDirty = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('saved_successfully', ref)));
      context.pop();
    }
  }

  void _toggleSeller(String id, String name) {
    setState(() {
      final idx = _selectedSellerIds.indexOf(id);
      if (idx >= 0) {
        _selectedSellerIds.removeAt(idx);
        _selectedSellerNames.removeAt(idx);
      } else {
        _selectedSellerIds.add(id);
        _selectedSellerNames.add(name);
      }
      _isDirty = true;
    });
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

    final sellers = ref.watch(sellersProvider).value ?? [];
    final cs = Theme.of(context).colorScheme;

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
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  // Currency selector
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: InputDecoration(labelText: tr('currency', ref)),
                    items: const [
                      DropdownMenuItem(value: 'SAR', child: Text('SAR (﷼)')),
                      DropdownMenuItem(value: 'PKR', child: Text('PKR (Rs)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _currency = v);
                      _isDirty = true;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Multi-seller selection chips
                  Text(
                    tr('assigned_sellers', ref),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (sellers.isEmpty)
                    Text(
                      tr('no_sellers', ref),
                      style: TextStyle(color: cs.outline),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: sellers.map((s) {
                        final selected = _selectedSellerIds.contains(s.id);
                        return FilterChip(
                          label: Text(
                            s.displayName,
                            style: AppFonts.userName(
                              ref.watch(appLocaleProvider).locale.languageCode,
                              fontSize: 13,
                              color: cs.onSurface,
                            ),
                          ),
                          selected: selected,
                          onSelected: (_) => _toggleSeller(s.id, s.displayName),
                        );
                      }).toList(),
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
