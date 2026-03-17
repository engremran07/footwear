import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/user_provider.dart';
import '../models/settings_model.dart';
import '../widgets/error_state.dart';
import '../widgets/role_guard.dart';
import '../core/utils/validators.dart';
import '../core/l10n/app_locale.dart';
import '../core/constants/app_brand.dart';
import '../core/utils/app_message.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('settings', ref))),
      body: settingsAsync.when(
        data: (settings) => _SettingsForm(existing: settings),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  final SettingsModel? existing;
  const _SettingsForm({this.existing});

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  final _companyNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _taxRateCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController();
  final _pkRateCtrl = TextEditingController();
  final _ksaRateCtrl = TextEditingController();
  final _exchangeRateCtrl = TextEditingController();
  String _currencyPrimary = 'SAR';
  String _currencySecondary = 'PKR';
  List<String> _productCategories = [];
  List<String> _expenseCategories = [];
  List<String> _qcRejectReasons = [];
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _taxRateCtrl.dispose();
    _lowStockCtrl.dispose();
    _pkRateCtrl.dispose();
    _ksaRateCtrl.dispose();
    _exchangeRateCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initFrom(widget.existing);
  }

  void _initFrom(SettingsModel? s) {
    if (_initialized || s == null) return;
    _initialized = true;
    _companyNameCtrl.text = s.companyName;
    _addressCtrl.text = s.companyAddress;
    _phoneCtrl.text = s.companyPhone;
    _taxRateCtrl.text = s.taxRate.toString();
    _lowStockCtrl.text = s.lowStockThreshold.toString();
    _pkRateCtrl.text = s.defaultPkRate.toString();
    _ksaRateCtrl.text = s.defaultKsaRate.toString();
    _exchangeRateCtrl.text = s.exchangeRatePkrToSar.toString();
    _currencyPrimary = s.currencyPrimary;
    _currencySecondary = s.currencySecondary;
    _productCategories = List.from(s.productCategories);
    _expenseCategories = List.from(s.expenseCategories);
    _qcRejectReasons = List.from(s.qcRejectReasons);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(settingsNotifierProvider.notifier).save({
        'company_name': _companyNameCtrl.text.trim(),
        'company_address': _addressCtrl.text.trim(),
        'company_phone': _phoneCtrl.text.trim(),
        'currency_primary': _currencyPrimary,
        'currency_secondary': _currencySecondary,
        'tax_rate': double.tryParse(_taxRateCtrl.text) ?? 0.0,
        'low_stock_threshold': int.tryParse(_lowStockCtrl.text) ?? 10,
        'default_pk_rate': double.tryParse(_pkRateCtrl.text) ?? 85.0,
        'default_ksa_rate': double.tryParse(_ksaRateCtrl.text) ?? 15.0,
        'exchange_rate_pkr_to_sar':
            double.tryParse(_exchangeRateCtrl.text) ?? 0.013,
        'product_categories': _productCategories,
        'expense_categories': _expenseCategories,
        'qc_reject_reasons': _qcRejectReasons,
      });
      if (mounted) {
        AppMessage.success(context, ref, 'settings_saved');
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _initFrom(widget.existing);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Language ─────────────────────────────────────────────────────
          const _SectionHeader(
              title: 'Language / اللغة / زبان', icon: Icons.language),
          const SizedBox(height: 8),
          _LanguageSwitcher(),
          const SizedBox(height: 24),
          // ── Company ──────────────────────────────────────────────────────
          _SectionHeader(title: tr('company', ref), icon: Icons.business),
          const SizedBox(height: 8),
          TextFormField(
            controller: _companyNameCtrl,
            decoration: InputDecoration(
                labelText: '${tr('company_name', ref)} *',
                border: const OutlineInputBorder()),
            validator: Validators.notEmpty,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressCtrl,
            decoration: InputDecoration(
                labelText: tr('address', ref),
                border: const OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            decoration: InputDecoration(
                labelText: tr('phone', ref),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.phone)),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          // ── Currency ─────────────────────────────────────────────────────
          _SectionHeader(
              title: tr('currency', ref), icon: Icons.currency_exchange),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
                labelText: tr('primary_currency', ref),
                border: const OutlineInputBorder()),
            initialValue: _currencyPrimary,
            items: const [
              DropdownMenuItem(value: 'SAR', child: Text('SAR – Saudi Riyal')),
              DropdownMenuItem(
                  value: 'PKR', child: Text('PKR – Pakistani Rupee')),
              DropdownMenuItem(value: 'USD', child: Text('USD – US Dollar')),
            ],
            onChanged: (v) => setState(() => _currencyPrimary = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
                labelText: tr('secondary_currency', ref),
                border: const OutlineInputBorder()),
            initialValue: _currencySecondary,
            items: const [
              DropdownMenuItem(
                  value: 'PKR', child: Text('PKR – Pakistani Rupee')),
              DropdownMenuItem(value: 'SAR', child: Text('SAR – Saudi Riyal')),
              DropdownMenuItem(value: 'USD', child: Text('USD – US Dollar')),
            ],
            onChanged: (v) => setState(() => _currencySecondary = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _exchangeRateCtrl,
            decoration: InputDecoration(
                labelText: tr('exchange_rate_pkr_to_sar', ref),
                helperText: '1 PKR = ? SAR',
                border: const OutlineInputBorder()),
            keyboardType: TextInputType.number,
            validator: Validators.nonNegativeDouble,
          ),
          const SizedBox(height: 24),
          // ── Thresholds ───────────────────────────────────────────────────
          _SectionHeader(title: tr('thresholds_tax', ref), icon: Icons.tune),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _taxRateCtrl,
                  decoration: InputDecoration(
                      labelText: tr('tax_rate', ref),
                      border: const OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: Validators.nonNegativeDouble,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _lowStockCtrl,
                  decoration: InputDecoration(
                      labelText: tr('low_stock_threshold', ref),
                      border: const OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: Validators.positiveInt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Worker Defaults ──────────────────────────────────────────────
          _SectionHeader(
              title: tr('worker_default_rates', ref), icon: Icons.people),
          const SizedBox(height: 4),
          Text(tr('worker_rate_hint', ref),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _pkRateCtrl,
                  decoration: InputDecoration(
                      labelText: tr('pk_rate', ref),
                      border: const OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: Validators.nonNegativeDouble,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _ksaRateCtrl,
                  decoration: InputDecoration(
                      labelText: tr('ksa_rate', ref),
                      border: const OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: Validators.nonNegativeDouble,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Product Categories ───────────────────────────────────────────
          _SectionHeader(
              title: tr('product_categories', ref), icon: Icons.category),
          const SizedBox(height: 4),
          Text(tr('product_cat_hint', ref),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          _TagListEditor(
            items: _productCategories,
            onChanged: (v) => setState(() => _productCategories = v),
            hint: 'e.g. Formal',
          ),
          const SizedBox(height: 24),
          // ── Expense Categories ───────────────────────────────────────────
          _SectionHeader(
              title: tr('expense_categories', ref), icon: Icons.receipt_long),
          const SizedBox(height: 4),
          Text(tr('expense_cat_hint', ref),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          _TagListEditor(
            items: _expenseCategories,
            onChanged: (v) => setState(() => _expenseCategories = v),
            hint: 'e.g. utilities',
          ),
          const SizedBox(height: 24),
          // ── QC Rejection Reasons ─────────────────────────────────────────
          _SectionHeader(
              title: tr('qc_reject_reasons', ref), icon: Icons.block),
          const SizedBox(height: 4),
          Text(tr('qc_reasons_hint', ref),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          _TagListEditor(
            items: _qcRejectReasons,
            onChanged: (v) => setState(() => _qcRejectReasons = v),
            hint: 'e.g. stitching_issue',
          ),
          const SizedBox(height: 24),
          RoleGuard(
            allowed: (u) => u.isAdmin,
            child: FilledButton.icon(
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(tr('save_all_settings', ref)),
              onPressed: _saving ? null : _submit,
            ),
          ),
          const SizedBox(height: 24),
          _AccountSection(),
          const SizedBox(height: 24),
          RoleGuard(
            allowed: (u) => u.isAdmin,
            child: _UserManagementSection(),
          ),
          const SizedBox(height: 24),
          // ── About Us ─────────────────────────────────────────────────────
          _SectionHeader(title: tr('about_us', ref), icon: Icons.info_outline),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(AppBrand.aboutDescription,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: 24),
          // ── Contact Us ───────────────────────────────────────────────────
          _SectionHeader(
              title: tr('contact_us', ref), icon: Icons.mail_outline),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.email_outlined),
                  title: Text('Email'),
                  subtitle: Text(AppBrand.contactEmail),
                  dense: true,
                ),
                ListTile(
                  leading: Icon(Icons.phone_outlined),
                  title: Text('Phone'),
                  subtitle: Text(AppBrand.contactPhone),
                  dense: true,
                ),
                ListTile(
                  leading: Icon(Icons.language),
                  title: Text('Website'),
                  subtitle: Text(AppBrand.websiteUrl),
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ── App Version ──────────────────────────────────────────────────
          _SectionHeader(
              title: tr('app_version', ref), icon: Icons.verified_outlined),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.phone_android),
              title: Text(AppBrand.appName),
              subtitle: Text(AppBrand.versionDisplay),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const Expanded(child: Divider(indent: 8)),
      ],
    );
  }
}

// ─── Tag List Editor ──────────────────────────────────────────────────────
// Lets admin add/remove items from a list (categories, reasons, etc.)

class _TagListEditor extends StatefulWidget {
  final List<String> items;
  final ValueChanged<List<String>> onChanged;
  final String hint;
  const _TagListEditor(
      {required this.items, required this.onChanged, required this.hint});

  @override
  State<_TagListEditor> createState() => _TagListEditorState();
}

class _TagListEditorState extends State<_TagListEditor> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final v = _ctrl.text.trim();
    if (v.isEmpty || widget.items.contains(v)) return;
    final updated = [...widget.items, v];
    widget.onChanged(updated);
    _ctrl.clear();
  }

  void _remove(String item) {
    widget.onChanged(widget.items.where((e) => e != item).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...widget.items.map(
              (item) => Chip(
                label: Text(item),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => _remove(item),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _add,
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(12)),
              child: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Language Switcher ────────────────────────────────────────────────────

class _LanguageSwitcher extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appLocaleProvider);
    return SegmentedButton<AppLocale>(
      segments: AppLocale.values
          .map((l) => ButtonSegment<AppLocale>(value: l, label: Text(l.label)))
          .toList(),
      selected: {current},
      onSelectionChanged: (sel) {
        ref.read(appLocaleProvider.notifier).state = sel.first;
      },
    );
  }
}

// ─── Account Section ──────────────────────────────────────────────────────

class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('account_section', ref),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (user != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(user.displayName),
            subtitle: Text('${user.email} · ${user.role.name}'),
            trailing: const Icon(Icons.account_circle),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: Text(tr('sign_out', ref)),
          onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// User Management (admin only)
// ───────────────────────────────────────────────────────────────────────────

class _UserManagementSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(allUsersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr('user_accounts', ref),
                style: Theme.of(context).textTheme.titleSmall),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.person_add, size: 18),
              label: Text(tr('add_user', ref)),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const _CreateUserDialog(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        usersAsync.when(
          data: (users) => users.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(tr('no_users', ref)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _UserRow(user: users[i]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('${tr('error', ref)}: $e'),
        ),
      ],
    );
  }
}

class _UserRow extends ConsumerWidget {
  final UserModel user;
  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(userManagementNotifierProvider.notifier);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
          user.displayName.isEmpty ? tr('no_name', ref) : user.displayName),
      subtitle: Text(user.email),
      leading: _RoleChip(role: user.role),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: user.active ? tr('active', ref) : tr('inactive', ref),
            child: Switch(
              value: user.active,
              onChanged: (v) async {
                try {
                  await notifier.setActive(user.id, active: v);
                } catch (e) {
                  if (context.mounted) {
                    AppMessage.error(context, ref, e);
                  }
                }
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: tr('edit_role', ref),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _EditUserDialog(user: user),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final UserRole role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      UserRole.admin => ('Admin', Colors.deepPurple),
      UserRole.manager => ('Manager', Colors.blue),
      UserRole.viewer => ('Viewer', Colors.grey),
      UserRole.workerPk => ('Worker PK', Colors.green),
      UserRole.workerKsa => ('Worker KSA', Colors.teal),
      UserRole.seller => ('Seller', Colors.orange),
    };
    return Chip(
      label: Text(label,
          style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ─── Permission Checkbox Grid (shared between Create & Edit) ──────────────

class _PermissionGrid extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final WidgetRef ref;

  const _PermissionGrid({
    required this.selected,
    required this.onChanged,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(tr('permissions', ref), style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton(
              onPressed: () => onChanged(AppPermissions.all.toSet()),
              child: Text(tr('select_all', ref),
                  style: const TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: () => onChanged({}),
              child: Text(tr('deselect_all', ref),
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...AppPermissions.grouped.entries.map((entry) {
          final cat = entry.key;
          final perms = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 2),
                child: Text(
                  tr('cat_$cat', ref),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Wrap(
                spacing: 0,
                runSpacing: 0,
                children: perms.map((p) {
                  final isSelected = selected.contains(p);
                  return SizedBox(
                    width: 220,
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(tr('perm_$p', ref),
                          style: const TextStyle(fontSize: 13)),
                      value: isSelected,
                      onChanged: (v) {
                        final next = Set<String>.from(selected);
                        if (v == true) {
                          next.add(p);
                        } else {
                          next.remove(p);
                        }
                        onChanged(next);
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ─── Create User Dialog ───────────────────────────────────────────────────

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _workerIdCtrl = TextEditingController();
  UserRole _role = UserRole.viewer;
  String _country = 'KSA';
  String _currency = 'SAR';
  late Set<String> _perms;
  bool _obscurePassword = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _perms = AppPermissions.defaultsForRole(_role).toSet();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _workerIdCtrl.dispose();
    super.dispose();
  }

  bool get _needsWorkerId =>
      _role == UserRole.workerPk || _role == UserRole.workerKsa;

  void _onRoleChanged(UserRole role) {
    setState(() {
      _role = role;
      _perms = AppPermissions.defaultsForRole(role).toSet();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(userManagementNotifierProvider.notifier).createUser(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            displayName: _nameCtrl.text,
            role: _role,
            permissions: _perms.toList(),
            workerId: _needsWorkerId ? _workerIdCtrl.text.trim() : null,
            country: _country,
            currency: _currency,
          );
      if (mounted) {
        Navigator.of(context).pop();
        AppMessage.success(context, ref, 'user_created');
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('create_user_account', ref)),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: '${tr('display_name', ref)} *',
                    border: const OutlineInputBorder(),
                  ),
                  validator: Validators.notEmpty,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: '${tr('email', ref)} *',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  decoration: InputDecoration(
                    labelText: '${tr('temp_password', ref)} *',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (v) {
                    if (v == null || v.isEmpty) return tr('required', ref);
                    if (v.length < 6) return tr('min_6_chars', ref);
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  decoration: InputDecoration(
                    labelText: '${tr('role', ref)} *',
                    helperText: tr('select_role_template', ref),
                    border: const OutlineInputBorder(),
                  ),
                  initialValue: _role,
                  items: UserRole.values
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(tr('role_${_roleKey(r)}', ref)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _onRoleChanged(v);
                  },
                ),
                if (_needsWorkerId) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _workerIdCtrl,
                    decoration: InputDecoration(
                      labelText: '${tr('worker_id', ref)} *',
                      helperText: tr('worker_id_match_hint', ref),
                      border: const OutlineInputBorder(),
                    ),
                    validator: _needsWorkerId ? Validators.notEmpty : null,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: tr('country', ref),
                          border: const OutlineInputBorder(),
                        ),
                        initialValue: _country,
                        items: const [
                          DropdownMenuItem(
                              value: 'KSA', child: Text('KSA - Saudi Arabia')),
                          DropdownMenuItem(
                              value: 'PK', child: Text('PK - Pakistan')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _country = v;
                              _currency = v == 'PK' ? 'PKR' : 'SAR';
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: tr('currency', ref),
                          border: const OutlineInputBorder(),
                        ),
                        initialValue: _currency,
                        items: const [
                          DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                          DropdownMenuItem(value: 'PKR', child: Text('PKR')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _currency = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                _PermissionGrid(
                  selected: _perms,
                  onChanged: (v) => setState(() => _perms = v),
                  ref: ref,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('create_user_hint', ref),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(tr('cancel', ref)),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('create_user', ref)),
        ),
      ],
    );
  }
}

// ─── Edit User Dialog ─────────────────────────────────────────────────────

class _EditUserDialog extends ConsumerStatefulWidget {
  final UserModel user;
  const _EditUserDialog({required this.user});

  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  late UserRole _role;
  late bool _active;
  late Set<String> _perms;
  late String _country;
  late String _currency;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.user.role;
    _active = widget.user.active;
    _perms = widget.user.permissions.toSet();
    _country = widget.user.country;
    _currency = widget.user.currency;
  }

  void _onRoleChanged(UserRole role) {
    setState(() {
      _role = role;
      _perms = AppPermissions.defaultsForRole(role).toSet();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(userManagementNotifierProvider.notifier).updateUser(
            widget.user.id,
            role: _role,
            permissions: _perms.toList(),
            active: _active,
            country: _country,
            currency: _currency,
          );
      if (mounted) {
        Navigator.of(context).pop();
        AppMessage.success(context, ref, 'user_updated');
      }
    } catch (e) {
      if (mounted) {
        AppMessage.error(context, ref, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${tr('edit_user', ref)} — ${widget.user.displayName}'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('email', ref)),
                subtitle: Text(widget.user.email),
              ),
              const Divider(),
              DropdownButtonFormField<UserRole>(
                decoration: InputDecoration(
                  labelText: tr('role', ref),
                  helperText: tr('select_role_template', ref),
                  border: const OutlineInputBorder(),
                ),
                initialValue: _role,
                items: UserRole.values
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(tr('role_${_roleKey(r)}', ref)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) _onRoleChanged(v);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: tr('country', ref),
                        border: const OutlineInputBorder(),
                      ),
                      initialValue: _country,
                      items: const [
                        DropdownMenuItem(
                            value: 'KSA', child: Text('KSA - Saudi Arabia')),
                        DropdownMenuItem(
                            value: 'PK', child: Text('PK - Pakistan')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _country = v;
                            _currency = v == 'PK' ? 'PKR' : 'SAR';
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: tr('currency', ref),
                        border: const OutlineInputBorder(),
                      ),
                      initialValue: _currency,
                      items: const [
                        DropdownMenuItem(value: 'SAR', child: Text('SAR')),
                        DropdownMenuItem(value: 'PKR', child: Text('PKR')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('account_active', ref)),
                subtitle: Text(_active
                    ? tr('user_can_sign_in', ref)
                    : tr('user_blocked', ref)),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              const Divider(),
              _PermissionGrid(
                selected: _perms,
                onChanged: (v) => setState(() => _perms = v),
                ref: ref,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(tr('cancel', ref)),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('save', ref)),
        ),
      ],
    );
  }
}

/// Maps a [UserRole] enum to the locale key suffix.
String _roleKey(UserRole r) {
  switch (r) {
    case UserRole.admin:
      return 'admin';
    case UserRole.manager:
      return 'manager';
    case UserRole.viewer:
      return 'viewer';
    case UserRole.workerPk:
      return 'worker_pk';
    case UserRole.workerKsa:
      return 'worker_ksa';
    case UserRole.seller:
      return 'seller';
  }
}
