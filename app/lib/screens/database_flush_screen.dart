import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/snack_helper.dart';
import '../providers/auth_provider.dart';
import '../providers/database_flush_provider.dart';
import '../providers/user_provider.dart';

/// Dedicated screen for all destructive database flush operations.
/// Admin-only: redirects non-admins back immediately.
class DatabaseFlushScreen extends ConsumerStatefulWidget {
  const DatabaseFlushScreen({super.key});

  @override
  ConsumerState<DatabaseFlushScreen> createState() =>
      _DatabaseFlushScreenState();
}

class _DatabaseFlushScreenState extends ConsumerState<DatabaseFlushScreen> {
  bool _includeUsers = false;
  String? _selectedUserId;
  bool _flushing = false;

  Future<void> _executeFlush(
    String descKey,
    Future<FlushResult> Function() action,
  ) async {
    // Step 1: "Are you sure?" confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppBrand.errorColor,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('flush_confirm_title', ref))),
          ],
        ),
        content: Text(
          tr(
            'flush_confirm_message',
            ref,
          ).replaceAll('%s', tr(descKey, ref).toLowerCase()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel', ref)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppBrand.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('flush_confirm_button', ref)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Step 2: Password + countdown confirmation
    final passwordOk = await _showPasswordCountdownDialog();
    if (passwordOk != true || !mounted) return;

    // Step 3: Execute
    setState(() => _flushing = true);
    try {
      final result = await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          successSnackBar(
            tr(
              'flush_success',
              ref,
            ).replaceAll('%s', '${result.totalAffected}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
      }
    } finally {
      if (mounted) setState(() => _flushing = false);
    }
  }

  Future<bool?> _showPasswordCountdownDialog() {
    final passwordC = TextEditingController();
    int countdown = 10;
    String? errorText;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (countdown > 0) {
            Future.delayed(const Duration(seconds: 1), () {
              if (ctx.mounted && countdown > 0) {
                setS(() => countdown--);
              }
            });
          }
          return AlertDialog(
            title: Text(tr('flush_password_title', ref)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordC,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: tr('flush_password_hint', ref),
                    errorText: errorText,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  onChanged: (_) {
                    if (errorText != null) setS(() => errorText = null);
                  },
                ),
                const SizedBox(height: 16),
                if (countdown > 0)
                  Text(
                    tr('flush_countdown', ref).replaceAll('%s', '$countdown'),
                    style: const TextStyle(
                      color: AppBrand.warningColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('cancel', ref)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppBrand.errorColor,
                ),
                onPressed: countdown > 0 || passwordC.text.isEmpty
                    ? null
                    : () async {
                        final ok = await ref
                            .read(databaseFlushProvider.notifier)
                            .reauthenticate(passwordC.text);
                        if (ok) {
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } else {
                          setS(
                            () => errorText = tr('flush_password_wrong', ref),
                          );
                        }
                      },
                child: Text(tr('flush_confirm_button', ref)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _flushTile({
    required IconData icon,
    required String titleKey,
    required String descKey,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppBrand.errorColor),
      title: Text(
        tr(titleKey, ref),
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        tr(descKey, ref),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _flushing ? null : onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authUserProvider).value;
    if (currentUser == null || !currentUser.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('danger_zone', ref))),
        body: Center(child: Text(tr('permission_denied', ref))),
      );
    }
    final users = ref.watch(allUsersProvider).value ?? [];
    final nonAdminUsers = users.where((u) => !u.isAdmin).toList();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            backgroundColor: AppBrand.errorColor.withAlpha(20),
            iconTheme: const IconThemeData(color: AppBrand.errorColor),
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppBrand.errorColor,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  tr('danger_zone', ref),
                  style: const TextStyle(
                    color: AppBrand.errorColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Warning banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppBrand.errorColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppBrand.errorColor.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppBrand.errorColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('danger_zone_subtitle', ref),
                        style: TextStyle(
                          color: AppBrand.errorColor.withAlpha(220),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Individual flush options
              Card(
                child: Column(
                  children: [
                    _flushTile(
                      icon: Icons.receipt_long_outlined,
                      titleKey: 'flush_financial',
                      descKey: 'flush_financial_desc',
                      onTap: () => _executeFlush(
                        'flush_financial_desc',
                        () => ref
                            .read(databaseFlushProvider.notifier)
                            .flushFinancialData(),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    _flushTile(
                      icon: Icons.inventory_2_outlined,
                      titleKey: 'flush_inventory',
                      descKey: 'flush_inventory_desc',
                      onTap: () => _executeFlush(
                        'flush_inventory_desc',
                        () => ref
                            .read(databaseFlushProvider.notifier)
                            .flushInventory(),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    _flushTile(
                      icon: Icons.store_outlined,
                      titleKey: 'flush_shops',
                      descKey: 'flush_shops_desc',
                      onTap: () => _executeFlush(
                        'flush_shops_desc',
                        () => ref
                            .read(databaseFlushProvider.notifier)
                            .flushShops(),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    _flushTile(
                      icon: Icons.route_outlined,
                      titleKey: 'flush_routes',
                      descKey: 'flush_routes_desc',
                      onTap: () => _executeFlush(
                        'flush_routes_desc',
                        () => ref
                            .read(databaseFlushProvider.notifier)
                            .flushRoutes(),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    _flushTile(
                      icon: Icons.shopping_bag_outlined,
                      titleKey: 'flush_products',
                      descKey: 'flush_products_desc',
                      onTap: () => _executeFlush(
                        'flush_products_desc',
                        () => ref
                            .read(databaseFlushProvider.notifier)
                            .flushProducts(),
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    _flushTile(
                      icon: Icons.settings_backup_restore,
                      titleKey: 'flush_settings',
                      descKey: 'flush_settings_desc',
                      onTap: () => _executeFlush(
                        'flush_settings_desc',
                        () => ref
                            .read(databaseFlushProvider.notifier)
                            .resetSettings(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Per-user flush
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('flush_per_user', ref),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppBrand.errorColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('flush_per_user_desc', ref),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedUserId,
                        decoration: InputDecoration(
                          labelText: tr('flush_select_user', ref),
                          isDense: true,
                        ),
                        items: nonAdminUsers
                            .map(
                              (u) => DropdownMenuItem(
                                value: u.id,
                                child: Text(u.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: _flushing
                            ? null
                            : (v) => setState(() => _selectedUserId = v),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppBrand.errorColor,
                            side: const BorderSide(color: AppBrand.errorColor),
                          ),
                          onPressed: _flushing || _selectedUserId == null
                              ? null
                              : () => _executeFlush(
                                  'flush_per_user_desc',
                                  () => ref
                                      .read(databaseFlushProvider.notifier)
                                      .flushPerUser(_selectedUserId!),
                                ),
                          icon: const Icon(
                            Icons.person_remove_outlined,
                            size: 18,
                          ),
                          label: Text(tr('flush_per_user', ref)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Nuclear option — full reset
              Card(
                color: AppBrand.errorColor.withAlpha(15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppBrand.errorColor.withAlpha(80)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('flush_all', ref),
                        style: const TextStyle(
                          color: AppBrand.errorColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('flush_all_desc', ref),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppBrand.errorColor.withAlpha(180),
                        ),
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeUsers,
                        onChanged: _flushing
                            ? null
                            : (v) => setState(() => _includeUsers = v ?? false),
                        title: Text(
                          tr('flush_include_users', ref),
                          style: const TextStyle(fontSize: 14),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppBrand.errorColor,
                          ),
                          onPressed: _flushing
                              ? null
                              : () => _executeFlush(
                                  'flush_all_desc',
                                  () => ref
                                      .read(databaseFlushProvider.notifier)
                                      .flushAll(
                                        keepAdminId: currentUser.id,
                                        includeUsers: _includeUsers,
                                      ),
                                ),
                          icon: const Icon(Icons.delete_forever, size: 20),
                          label: Text(
                            tr('flush_all', ref).toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),

        // Full-screen loading overlay
        if (_flushing)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      tr('flush_in_progress', ref),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
