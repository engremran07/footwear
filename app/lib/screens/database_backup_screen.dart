import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants/app_brand.dart';
import '../core/l10n/app_locale.dart';
import '../core/services/google_drive_backup_service.dart';
import '../core/utils/error_mapper.dart';
import '../core/utils/backup_scope_policy.dart';
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

  // ── prefs state ───────────────────────────────────────────────────────────
  bool _autoEnabled = false;
  int _intervalMinutes = 1440;
  DateTime? _lastBackupAt;
  DateTime? _lastRestoreAt;
  String? _lastRestoreBy;

  // ── collection selection ──────────────────────────────────────────────────
  final Set<String> _selected = {};

  static final _dateFmt = DateFormat('MMM d, y \'at\' h:mm a');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final n = ref.read(databaseBackupProvider.notifier);
    final user = await ref.read(authUserProvider.future);
    final auto = await n.getAutoEnabled();
    final interval = await n.getIntervalMinutes();
    final lastBackup = await n.getLastBackupAt();
    final lastRestore = await n.getLastRestoreAt();
    final lastRestoreBy = await n.getLastRestoreBy();
    if (mounted) {
      _selected
        ..clear()
        ..addAll(
          user == null
              ? const <String>{}
              : BackupScopePolicy.collectionsFor(user.role),
        );
      setState(() {
        _autoEnabled = auto;
        _intervalMinutes = interval;
        _lastBackupAt = lastBackup;
        _lastRestoreAt = lastRestore;
        _lastRestoreBy = lastRestoreBy;
        _loadingPrefs = false;
      });
    }
  }

  String _fmt(DateTime dt) => _dateFmt.format(dt.toLocal());

  Future<String?> _requestBackupPassphrase({
    required bool confirmPassphrase,
  }) async {
    final passwordC = TextEditingController();
    final confirmationC = TextEditingController();
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr('backup_encryption_title', ref)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('backup_encryption_hint', ref)),
              const SizedBox(height: 12),
              TextField(
                controller: passwordC,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr('backup_passphrase', ref),
                  errorText: errorText,
                ),
              ),
              if (confirmPassphrase) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: confirmationC,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: tr('backup_passphrase_confirm', ref),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('cancel', ref)),
            ),
            FilledButton(
              onPressed: () {
                if (passwordC.text.trim().length < 12) {
                  setDialogState(
                    () => errorText = tr('backup_passphrase_too_short', ref),
                  );
                  return;
                }
                if (confirmPassphrase && passwordC.text != confirmationC.text) {
                  setDialogState(
                    () => errorText = tr('backup_passphrase_mismatch', ref),
                  );
                  return;
                }
                Navigator.pop(dialogContext, passwordC.text);
              },
              child: Text(tr('backup_restore_proceed', ref)),
            ),
          ],
        ),
      ),
    );
    passwordC.dispose();
    confirmationC.dispose();
    return result;
  }

  // ── Backup ─────────────────────────────────────────────────────────────────

  Future<void> _doBackup() async {
    if (_selected.isEmpty) return;
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.canCreateWorkspaceBackup) return;
    final workspaceId = _workspaceIdFor(user);
    final passphrase = await _requestBackupPassphrase(confirmPassphrase: true);
    if (passphrase == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(databaseBackupProvider.notifier)
          .createBackup(
            selected: Set.unmodifiable(_selected),
            encryptionPassword: passphrase,
            tenantIdOverride: workspaceId,
          );
      if (!mounted) return;
      setState(() {
        _lastBackupAt = DateTime.now();
        _loading = false;
      });
      await shareFile(
        bytes: result.bytes,
        fileName: result.fileName,
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
    if (user == null || !user.canCreateWorkspaceBackup) return;
    final workspaceId = _workspaceIdFor(user);
    final passphrase = await _requestBackupPassphrase(confirmPassphrase: false);
    if (passphrase == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final notifier = ref.read(databaseBackupProvider.notifier);
      final result = await notifier.createBackup(
        selected: Set.unmodifiable(_selected),
        encryptionPassword: passphrase,
        tenantIdOverride: workspaceId,
      );
      await notifier.uploadBackupToDrive(
        bytes: result.bytes,
        fileName: result.fileName,
        encryptionPassword: passphrase,
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
    if (!user.canRestoreWorkspaceBackup) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('backup_restore_scope_denied', ref)));
      return;
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
        builder: (_) => _DriveFilePickerSheet(files: files, fmtDate: _fmt),
      );
      if (picked == null || !mounted) return;
      final bytes = await ref
          .read(databaseBackupProvider.notifier)
          .downloadDriveBackup(picked.id, tenantIdOverride: workspaceId);
      final passphrase = await _requestBackupPassphrase(
        confirmPassphrase: false,
      );
      if (passphrase == null || !mounted) return;
      final preview = await ref
          .read(databaseBackupProvider.notifier)
          .decryptAndVerifyBackup(archiveBytes: bytes, passphrase: passphrase);
      if (!mounted ||
          await _showPreviewDialog(
                preview,
                mergeRestore:
                    user.isTenantAdmin || preview.scope == 'platform_metadata',
              ) !=
              true) {
        return;
      }
      if (!mounted || await _showPasswordCountdownDialog() != true) return;
      final adminName = user.displayName.trim().isNotEmpty
          ? user.displayName
          : (user.email.isNotEmpty ? user.email : 'admin');
      setState(() => _restoring = true);
      final count = await ref
          .read(databaseBackupProvider.notifier)
          .restoreFromBackup(preview, adminName: adminName);
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

  String? _workspaceIdFor(UserModel user) {
    return TenantScope.normalize(user.tenantId);
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
    if (!user.canRestoreWorkspaceBackup) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('backup_restore_scope_denied', ref)));
      return;
    }
    final workspaceId = _workspaceIdFor(user);
    if (workspaceId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(warningSnackBar(tr('select_workspace', ref)));
      return;
    }
    final backups = await ref
        .read(databaseBackupProvider.notifier)
        .listLocalBackups(tenantId: workspaceId, creatorUid: user.id);
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

    final passphrase = await _requestBackupPassphrase(confirmPassphrase: false);
    if (passphrase == null || !mounted) return;

    // 2 — decrypt and verify the file
    BackupPreview preview;
    try {
      final bytes = await picked.file.readAsBytes();
      preview = await ref
          .read(databaseBackupProvider.notifier)
          .decryptAndVerifyBackup(archiveBytes: bytes, passphrase: passphrase);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(errorSnackBar(tr('backup_restore_invalid', ref)));
      return;
    }

    // 3 — show preview + confirm
    final confirmed = await _showPreviewDialog(
      preview,
      mergeRestore: user.isTenantAdmin || preview.scope == 'platform_metadata',
    );
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
          .restoreFromBackup(preview, adminName: adminName);
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

  Future<bool?> _showPreviewDialog(
    BackupPreview preview, {
    bool mergeRestore = false,
  }) {
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
              if (mergeRestore) ...[
                Text(
                  tr('backup_restore_merge_warning', ref),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
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
    if (value) {
      if (!GoogleDriveBackupService.isConfigured) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(errorSnackBar(tr('backup_drive_not_configured', ref)));
        }
        return;
      }
      final passphrase = await _requestBackupPassphrase(
        confirmPassphrase: true,
      );
      if (passphrase == null || !mounted) return;
      await ref
          .read(databaseBackupProvider.notifier)
          .rememberAutoBackupPassphrase(passphrase);
    }
    await ref.read(databaseBackupProvider.notifier).setAutoEnabled(value);
    if (!value) {
      await ref
          .read(databaseBackupProvider.notifier)
          .clearAutoBackupPassphrase();
    }
    setState(() => _autoEnabled = value);
  }

  Future<void> _setInterval(int days) async {
    final minutes = days * 24 * 60;
    await ref.read(databaseBackupProvider.notifier).setIntervalMinutes(minutes);
    setState(() {
      _intervalMinutes = minutes;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).value;
    final tenants = ref.watch(tenantsProvider).value ?? const [];
    final activeTenantId = TenantScope.normalize(user?.tenantId);
    final activeTenantMatches = tenants
        .where((tenant) => tenant.id == activeTenantId)
        .toList();
    final activeTenantName = activeTenantId == null
      ? tr('select_workspace', ref)
      : activeTenantMatches.isEmpty
      ? tr('workspace_name_unavailable', ref)
      : activeTenantMatches.first.name;
    final canUseBackup =
        user?.active == true && user?.canCreateWorkspaceBackup == true;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(tr('backup_title', ref)),
            backgroundColor: AppBrand.primaryColor,
            foregroundColor: AppBrand.onPrimary,
          ),
          body: !canUseBackup
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
                        child: ListTile(
                          leading: const Icon(Icons.domain_outlined),
                          title: Text(tr('workspace_access_active', ref)),
                          subtitle: Text(activeTenantName),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Auto-backup Card ─────────────────────────────
                    if (user?.canRunAutomaticWorkspaceBackup == true && !kIsWeb)
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
                                subtitle: Text(
                                  GoogleDriveBackupService.isConfigured
                                      ? tr('backup_auto_subtitle', ref)
                                      : tr('backup_drive_not_configured', ref),
                                ),
                                value: _autoEnabled,
                                onChanged: GoogleDriveBackupService.isConfigured
                                    ? _setAutoEnabled
                                    : null,
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
                                    value: (_intervalMinutes / 24 / 60)
                                        .round()
                                        .clamp(1, 30),
                                    underline: const SizedBox.shrink(),
                                    onChanged: (v) {
                                      if (v != null) _setInterval(v);
                                    },
                                    items: [
                                      DropdownMenuItem(
                                        value: 1,
                                        child: Text(
                                          tr('backup_interval_1', ref),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 3,
                                        child: Text(
                                          tr('backup_interval_3', ref),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 7,
                                        child: Text(
                                          tr('backup_interval_7', ref),
                                        ),
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
                                tr(
                                  user!.isSuperAdmin
                                      ? 'backup_platform_metadata_subtitle'
                                      : 'backup_workspace_backup_subtitle',
                                  ref,
                                ),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppBrand.stockColor),
                              ),
                            ),
                            for (final collectionKey
                                in BackupScopePolicy.collectionsFor(user.role))
                              _CollectionTile(
                                collectionKey: collectionKey,
                                labelKey: _backupCollectionLabelKey(
                                  collectionKey,
                                ),
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
                      onPressed:
                          _loading || !GoogleDriveBackupService.isConfigured
                          ? null
                          : _doDriveBackup,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(tr('backup_to_google_drive', ref)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    if (!GoogleDriveBackupService.isConfigured)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tr('backup_drive_not_configured', ref),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppBrand.warningColor),
                        ),
                      ),
                    const SizedBox(height: 32),

                    if (user.canRestoreWorkspaceBackup) ...[
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
                      if (!kIsWeb)
                        OutlinedButton.icon(
                          onPressed: _restoring ? null : _pickAndRestore,
                          icon: _restoring
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                      if (user.active) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed:
                              _restoring ||
                                  !GoogleDriveBackupService.isConfigured
                              ? null
                              : _pickAndRestoreFromDrive,
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: Text(tr('restore_from_google_drive', ref)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
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

  String _backupCollectionLabelKey(String collectionKey) =>
      switch (collectionKey) {
        'workspaces' => 'backup_workspaces',
        'users' => 'backup_users',
        'routes' => 'backup_routes',
        'shops' => 'backup_shops',
        'products' => 'backup_products',
        'inventory' => 'backup_inventory',
        'transactions' => 'backup_transactions',
        'invoices' => 'backup_invoices',
        'settings' => 'backup_settings',
        _ => 'backup_title',
      };
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
  final String Function(DateTime) fmtDate;

  const _DriveFilePickerSheet({required this.files, required this.fmtDate});

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
            subtitle: Text(
              file.createdAt != null ? fmtDate(file.createdAt!.toLocal()) : '',
            ),
            onTap: () => Navigator.pop(context, file),
          );
        },
      ),
    );
  }
}
