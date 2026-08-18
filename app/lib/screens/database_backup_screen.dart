import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/services/google_drive_backup_service.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/share_helper.dart';
import '../core/utils/snack_helper.dart';
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/database_backup_provider.dart';
import '../providers/database_flush_provider.dart';
import '../providers/tenant_provider.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Full-featured backup & restore screen.
/// Active users can back up their permitted data; restore scope is role-based.
class DatabaseBackupScreen extends ConsumerStatefulWidget {
  const DatabaseBackupScreen({super.key});

  @override
  ConsumerState<DatabaseBackupScreen> createState() =>
      _DatabaseBackupScreenState();
}

class _DatabaseBackupScreenState extends ConsumerState<DatabaseBackupScreen> {
  // ── loading flags ──────────────────────────────────────────────────────────
  bool _loadingPrefs = true;
  bool _loading = false; // backup creation in progress
  bool _restoring = false; // restore in progress
  String? _selectedWorkspaceId;

  // ── prefs state ───────────────────────────────────────────────────────────
  bool _autoEnabled = false;
  int _intervalDays = 7;
  DateTime? _lastBackupAt;
  DateTime? _lastRestoreAt;
  String? _lastRestoreBy;

  // ── collection selection ──────────────────────────────────────────────────
  final Set<String> _selected = {
    'routes',
    'shops',
    'products',
    'inventory',
    'transactions',
    'invoices',
  };

  static final _dateFmt = DateFormat('MMM d, y \'at\' h:mm a');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final n = ref.read(databaseBackupProvider.notifier);
    final auto = await n.getAutoEnabled();
    final interval = await n.getIntervalDays();
    final lastBackup = await n.getLastBackupAt();
    final lastRestore = await n.getLastRestoreAt();
    final lastRestoreBy = await n.getLastRestoreBy();
    if (mounted) {
      setState(() {
        _autoEnabled = auto;
        _intervalDays = interval;
        _lastBackupAt = lastBackup;
        _lastRestoreAt = lastRestore;
        _lastRestoreBy = lastRestoreBy;
        _loadingPrefs = false;
      });
    }
  }

  String _fmt(DateTime dt) => _dateFmt.format(dt.toLocal());

  // ── Backup ─────────────────────────────────────────────────────────────────

  Future<void> _doBackup() async {
    if (_selected.isEmpty) return;
    final user = await ref.read(authUserProvider.future);
    if (user == null) return;
    final workspaceId = _workspaceIdFor(user);
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(databaseBackupProvider.notifier)
          .createBackup(
            selected: Set.unmodifiable(_selected),
            tenantIdOverride: workspaceId,
          );
      if (!mounted) return;
      setState(() {
        _lastBackupAt = DateTime.now();
        _loading = false;
      });
      final fileName = result.localPath.split('/').last.split('\\').last;
      await shareFile(
        bytes: result.bytes,
        fileName: fileName,
        mimeType: 'application/json',
        text: tr('backup_share_text', ref),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

  Future<void> _doDriveBackup() async {
    if (_selected.isEmpty) return;
    final user = await ref.read(authUserProvider.future);
    if (user == null) return;
    final workspaceId = _workspaceIdFor(user);
    setState(() => _loading = true);
    try {
      final notifier = ref.read(databaseBackupProvider.notifier);
      final result = await notifier.createBackup(
        selected: Set.unmodifiable(_selected),
        tenantIdOverride: workspaceId,
      );
      await notifier.uploadBackupToDrive(
        bytes: result.bytes,
        fileName: result.localPath.split('/').last.split('\\').last,
        tenantIdOverride: workspaceId,
      );
      if (!mounted) return;
      setState(() {
        _lastBackupAt = DateTime.now();
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(successSnackBar(tr('backup_drive_success', ref)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

  Future<void> _pickAndRestoreFromDrive() async {
    final user = await ref.read(authUserProvider.future);
    if (!mounted) return;
    if (user == null || !user.active) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('backup_restore_scope_denied', ref)));
      return;
    }
    String? selectedRouteId;
    if (user.isSeller) {
      selectedRouteId = await _chooseRestoreRoute(user);
      if (selectedRouteId == null || !mounted) return;
    }
    final workspaceId = _workspaceIdFor(user);
    try {
      final files = await ref
          .read(databaseBackupProvider.notifier)
          .listDriveBackups(tenantIdOverride: workspaceId);
      if (!mounted) return;
      if (files.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(infoSnackBar(tr('backup_drive_none', ref)));
        return;
      }
      final picked = await showModalBottomSheet<GoogleDriveBackupFile>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _DriveFilePickerSheet(files: files),
      );
      if (picked == null || !mounted) return;
      final bytes = await ref
          .read(databaseBackupProvider.notifier)
          .downloadDriveBackup(picked.id, tenantIdOverride: workspaceId);
      final preview = ref
          .read(databaseBackupProvider.notifier)
          .verifyBackup(bytes);
      if (!mounted || await _showPreviewDialog(preview) != true) return;
      if (!mounted || await _showPasswordCountdownDialog() != true) return;
      final adminName = user.displayName.trim().isNotEmpty
          ? user.displayName
          : (user.email.isNotEmpty ? user.email : 'admin');
      setState(() => _restoring = true);
      final count = await ref
          .read(databaseBackupProvider.notifier)
          .restoreFromBackup(
            preview,
            adminName: adminName,
            routeId: selectedRouteId,
          );
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _lastRestoreAt = DateTime.now();
        _lastRestoreBy = adminName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        successSnackBar(
          tr('backup_restore_success', ref).replaceAll('%s', '$count'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoring = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

  Future<String?> _chooseRestoreRoute(UserModel user) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('select_route', ref)),
        children: [
          for (var i = 0; i < user.assignedRouteIds.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, user.assignedRouteIds[i]),
              child: Text(
                user.assignedRouteNames.length > i &&
                        user.assignedRouteNames[i].trim().isNotEmpty
                    ? user.assignedRouteNames[i]
                    : user.assignedRouteIds[i],
              ),
            ),
        ],
      ),
    );
  }

  String? _workspaceIdFor(UserModel user) {
    final ownTenantId = TenantScope.normalize(user.tenantId);
    if (!user.isSuperAdmin) return ownTenantId;
    if (_selectedWorkspaceId != null) return _selectedWorkspaceId;
    final tenants = ref.read(tenantsProvider).value ?? const [];
    return tenants.isEmpty ? null : tenants.first.id;
  }

  // ── Restore ────────────────────────────────────────────────────────────────

  Future<void> _pickAndRestore() async {
    final user = await ref.read(authUserProvider.future);
    if (!mounted) return;
    if (user == null || !user.active) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('permission_denied', ref)));
      return;
    }
    String? selectedRouteId;
    if (user.isSeller) {
      selectedRouteId = await _chooseRestoreRoute(user);
      if (selectedRouteId == null || !mounted) return;
    }
    final backups = await ref
        .read(databaseBackupProvider.notifier)
        .listLocalBackups();
    if (!mounted) return;

    if (backups.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(infoSnackBar(tr('backup_no_local', ref)));
      return;
    }

    // 1 — pick a file from the local list
    final picked = await showModalBottomSheet<LocalBackupFile>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BackupFilePickerSheet(backups: backups, fmtDate: _fmt),
    );
    if (picked == null || !mounted) return;

    // 2 — verify the file
    BackupPreview preview;
    try {
      final bytes = await picked.file.readAsBytes();
      preview = ref.read(databaseBackupProvider.notifier).verifyBackup(bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('backup_restore_invalid', ref)));
      return;
    }

    // 3 — show preview + confirm
    final confirmed = await _showPreviewDialog(preview);
    if (confirmed != true || !mounted) return;

    // 4 — re-auth + countdown
    final authenticated = await _showPasswordCountdownDialog();
    if (authenticated != true || !mounted) return;

    // 5 — execute restore
    final adminName = user.displayName.isNotEmpty
      ? user.displayName
      : (user.email.isNotEmpty ? user.email : 'admin');

    setState(() => _restoring = true);
    try {
      final count = await ref
          .read(databaseBackupProvider.notifier)
          .restoreFromBackup(
            preview,
            adminName: adminName,
            routeId: selectedRouteId,
          );
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _lastRestoreAt = DateTime.now();
        _lastRestoreBy = adminName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        successSnackBar(
          tr('backup_restore_success', ref).replaceAll('%s', '$count'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoring = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr(AppErrorMapper.key(e), ref)));
    }
  }

  Future<bool?> _showPreviewDialog(BackupPreview preview) {
    final checksumOk = preview.checksumOk;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('backup_pick_file', ref)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning banner
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppBrand.errorColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppBrand.errorColor.withAlpha(80)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppBrand.errorColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('backup_restore_warning', ref),
                        style: const TextStyle(
                          color: AppBrand.errorColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Metadata
              Text(
                tr(
                  'backup_app_version',
                  ref,
                ).replaceAll('%s', preview.appVersion),
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                tr('backup_created_at', ref).replaceAll(
                  '%s',
                  preview.createdAt.length >= 10
                      ? preview.createdAt.substring(0, 10)
                      : preview.createdAt,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                tr(
                  'backup_total_records',
                  ref,
                ).replaceAll('%s', '${preview.totalRecords}'),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              // Per-collection record counts
              ...preview.counts.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Text('• ${e.key}:', style: const TextStyle(fontSize: 11)),
                      const Spacer(),
                      Text(
                        '${e.value}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Checksum result
              Row(
                children: [
                  Icon(
                    checksumOk
                        ? Icons.verified_outlined
                        : Icons.warning_outlined,
                    size: 14,
                    color: checksumOk
                        ? AppBrand.successColor
                        : AppBrand.warningColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      checksumOk
                          ? tr('backup_restore_checksum_ok', ref)
                          : tr('backup_restore_checksum_fail', ref),
                      style: TextStyle(
                        fontSize: 12,
                        color: checksumOk
                            ? AppBrand.successColor
                            : AppBrand.warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel', ref)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppBrand.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('backup_restore_proceed', ref)),
          ),
        ],
      ),
    );
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
              if (ctx.mounted && countdown > 0) setS(() => countdown--);
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
                child: Text(tr('backup_restore_proceed', ref)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Auto-backup prefs ──────────────────────────────────────────────────────

  Future<void> _setAutoEnabled(bool value) async {
    await ref.read(databaseBackupProvider.notifier).setAutoEnabled(value);
    setState(() => _autoEnabled = value);
  }

  Future<void> _setInterval(int days) async {
    await ref.read(databaseBackupProvider.notifier).setIntervalDays(days);
    setState(() => _intervalDays = days);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final tenants = ref.watch(tenantsProvider).value ?? const [];
    final isActive = user?.active ?? false;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(tr('backup_title', ref)),
            backgroundColor: AppBrand.primaryColor,
            foregroundColor: AppBrand.onPrimary,
          ),
          body: !isActive
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('permission_denied', ref),
                      style: const TextStyle(color: AppBrand.errorColor),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _loadingPrefs
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: [
                    // ── Status Card ──────────────────────────────────
                    _StatusCard(
                      lastBackupAt: _lastBackupAt,
                      lastRestoreAt: _lastRestoreAt,
                      lastRestoreBy: _lastRestoreBy,
                      fmt: _fmt,
                      never: tr('backup_never', ref),
                      lastAtTemplate: tr('backup_last_at', ref),
                      lastRestoreAtTemplate: tr('backup_last_restore_at', ref),
                      lastRestoreByTemplate: tr('backup_last_restore_by', ref),
                    ),
                    const SizedBox(height: 16),

                    if (user?.isSuperAdmin == true) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedWorkspaceId ??
                                (tenants.isNotEmpty ? tenants.first.id : null),
                            decoration: InputDecoration(
                              labelText: tr('workspaces', ref),
                            ),
                            items: tenants
                                .map(
                                  (tenant) => DropdownMenuItem<String>(
                                    value: tenant.id,
                                    child: Text(tenant.name),
                                  ),
                                )
                                .toList(),
                            onChanged: tenants.isEmpty
                                ? null
                                : (value) => setState(
                                      () => _selectedWorkspaceId = value,
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Auto-backup Card ─────────────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          children: [
                            SwitchListTile(
                              secondary: Icon(
                                Icons.schedule,
                                color: _autoEnabled
                                    ? AppBrand.primaryColor
                                    : AppBrand.stockColor,
                              ),
                              title: Text(tr('backup_auto_title', ref)),
                              subtitle: Text(tr('backup_auto_subtitle', ref)),
                              value: _autoEnabled,
                              onChanged: _setAutoEnabled,
                            ),
                            if (_autoEnabled) ...[
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
                              ListTile(
                                title: Text(tr('backup_interval', ref)),
                                trailing: DropdownButton<int>(
                                  value: _intervalDays,
                                  underline: const SizedBox.shrink(),
                                  onChanged: (v) {
                                    if (v != null) _setInterval(v);
                                  },
                                  items: [
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text(tr('backup_interval_1', ref)),
                                    ),
                                    DropdownMenuItem(
                                      value: 3,
                                      child: Text(tr('backup_interval_3', ref)),
                                    ),
                                    DropdownMenuItem(
                                      value: 7,
                                      child: Text(tr('backup_interval_7', ref)),
                                    ),
                                    DropdownMenuItem(
                                      value: 14,
                                      child: Text(
                                        tr('backup_interval_14', ref),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 30,
                                      child: Text(
                                        tr('backup_interval_30', ref),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Collections ──────────────────────────────────
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                              child: Text(
                                tr('backup_subtitle', ref),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppBrand.stockColor),
                              ),
                            ),
                            _CollectionTile(
                              collectionKey: 'routes',
                              labelKey: 'backup_routes',
                              selected: _selected,
                              onChanged: (fn) => setState(fn),
                            ),
                            _CollectionTile(
                              collectionKey: 'shops',
                              labelKey: 'backup_shops',
                              selected: _selected,
                              onChanged: (fn) => setState(fn),
                            ),
                            _CollectionTile(
                              collectionKey: 'products',
                              labelKey: 'backup_products',
                              selected: _selected,
                              onChanged: (fn) => setState(fn),
                            ),
                            _CollectionTile(
                              collectionKey: 'inventory',
                              labelKey: 'backup_inventory',
                              selected: _selected,
                              onChanged: (fn) => setState(fn),
                            ),
                            _CollectionTile(
                              collectionKey: 'transactions',
                              labelKey: 'backup_transactions',
                              selected: _selected,
                              onChanged: (fn) => setState(fn),
                            ),
                            _CollectionTile(
                              collectionKey: 'invoices',
                              labelKey: 'backup_invoices',
                              selected: _selected,
                              onChanged: (fn) => setState(fn),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Backup Now ───────────────────────────────────
                    FilledButton.icon(
                      onPressed: _loading ? null : _doBackup,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.backup_outlined),
                      label: Text(
                        _loading
                            ? tr('backup_in_progress', ref)
                            : tr('backup_now', ref),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppBrand.primaryColor,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _doDriveBackup,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(tr('backup_to_google_drive', ref)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Restore section ──────────────────────────────
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.restore,
                          color: AppBrand.warningColor,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('backup_restore', ref),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppBrand.warningColor,
                                ),
                              ),
                              Text(
                                tr('backup_restore_subtitle', ref),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppBrand.stockColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _restoring ? null : _pickAndRestore,
                      icon: _restoring
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.folder_open_outlined,
                              color: AppBrand.errorColor,
                            ),
                      label: Text(
                        _restoring
                            ? tr('backup_restore_in_progress', ref)
                            : tr('backup_restore', ref),
                        style: const TextStyle(color: AppBrand.errorColor),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppBrand.errorColor),
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    if (user?.active == true) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _restoring ? null : _pickAndRestoreFromDrive,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: Text(tr('restore_from_google_drive', ref)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'For cross-device or emergency recovery, use dev_restore.js '
                      'with Firebase Admin SDK.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppBrand.stockColor,
                      ),
                    ),
                  ],
                ),
        ),

        // ── Full-screen restore overlay ──────────────────────────────────
        if (_restoring)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      tr('backup_restore_in_progress', ref),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
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

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final DateTime? lastBackupAt;
  final DateTime? lastRestoreAt;
  final String? lastRestoreBy;
  final String Function(DateTime) fmt;
  final String never;
  final String lastAtTemplate;
  final String lastRestoreAtTemplate;
  final String lastRestoreByTemplate;

  const _StatusCard({
    required this.lastBackupAt,
    required this.lastRestoreAt,
    required this.lastRestoreBy,
    required this.fmt,
    required this.never,
    required this.lastAtTemplate,
    required this.lastRestoreAtTemplate,
    required this.lastRestoreByTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final backupLabel = lastAtTemplate.replaceAll(
      '%s',
      lastBackupAt != null ? fmt(lastBackupAt!) : never,
    );

    String restoreLabel;
    if (lastRestoreAt != null) {
      restoreLabel = lastRestoreAtTemplate.replaceAll(
        '%s',
        fmt(lastRestoreAt!),
      );
      if (lastRestoreBy?.isNotEmpty == true) {
        restoreLabel +=
            '  ${lastRestoreByTemplate.replaceAll('%s', lastRestoreBy!)}';
      }
    } else {
      restoreLabel = lastRestoreAtTemplate.replaceAll('%s', never);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            _StatusRow(
              icon: Icons.cloud_done_outlined,
              color: lastBackupAt != null
                  ? AppBrand.successColor
                  : AppBrand.stockColor,
              label: backupLabel,
            ),
            const SizedBox(height: 10),
            _StatusRow(
              icon: Icons.restore_page_outlined,
              color: lastRestoreAt != null
                  ? AppBrand.warningColor
                  : AppBrand.stockColor,
              label: restoreLabel,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _StatusRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _CollectionTile extends ConsumerWidget {
  final String collectionKey;
  final String labelKey;
  final Set<String> selected;
  final void Function(void Function()) onChanged;

  const _CollectionTile({
    required this.collectionKey,
    required this.labelKey,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CheckboxListTile(
      value: selected.contains(collectionKey),
      title: Text(tr(labelKey, ref)),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (v) => onChanged(() {
        if (v == true) {
          selected.add(collectionKey);
        } else {
          selected.remove(collectionKey);
        }
      }),
    );
  }
}

class _BackupFilePickerSheet extends StatelessWidget {
  final List<LocalBackupFile> backups;
  final String Function(DateTime) fmtDate;

  const _BackupFilePickerSheet({required this.backups, required this.fmtDate});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (ctx, ref, _) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollC) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr('backup_pick_file', ref),
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollC,
                itemCount: backups.length,
                itemBuilder: (_, i) {
                  final f = backups[i];
                  final sizeKb = (f.file.lengthSync() / 1024).toStringAsFixed(
                    0,
                  );
                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(f.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${fmtDate(f.modifiedAt)} · ${sizeKb}KB',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => Navigator.pop(ctx, f),
                      child: Text(tr('backup_restore_proceed', ref)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriveFilePickerSheet extends StatelessWidget {
  final List<GoogleDriveBackupFile> files;

  const _DriveFilePickerSheet({required this.files});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: files.length,
        itemBuilder: (_, index) {
          final file = files[index];
          return ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(file.name),
            subtitle: Text(file.createdAt?.toLocal().toString() ?? ''),
            onTap: () => Navigator.pop(context, file),
          );
        },
      ),
    );
  }
}
