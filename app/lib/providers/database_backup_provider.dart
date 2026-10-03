import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_brand.dart';
import '../core/constants/collections.dart';
import '../core/services/google_drive_backup_service.dart';
import '../core/utils/backup_cipher.dart';
import '../core/utils/backup_scope_policy.dart';
import '../core/utils/firestore_pagination.dart';
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

// ─── SharedPreferences keys ──────────────────────────────────────────────────
const _kAutoEnabled = 'backup_auto_enabled';
const _kIntervalMinutes = 'backup_interval_minutes';
const _kLegacyIntervalDays = 'backup_interval_days';
const _kLastBackupMs = 'backup_last_ms';
const _kLastDriveBackupMs = 'backup_last_drive_ms';
const _kLastRestoreMs = 'backup_last_restore_ms';
const _kLastRestoreBy = 'backup_last_restore_by';
const _backupSecretStorage = FlutterSecureStorage();

// ─── Helper functions ────────────────────────────────────────────────────────

/// P1-12 FIX: Derive per-tenant settings doc ID from user profile.
/// Matches the pattern used in settings_provider.dart.
String _settingsDocumentIdForCurrentUser(UserModel? currentUser) {
  return TenantScope.requireTenant(currentUser?.tenantId);
}

// ─── Data classes ─────────────────────────────────────────────────────────────

/// Metadata parsed from a backup JSON file, shown to the admin before restore.
class BackupPreview {
  final String appVersion;
  final String createdAt;
  final String? createdByUid;
  final String tenantId;
  final String scope;
  final List<String> routeIds;
  final Map<String, int> counts;
  final bool checksumOk;
  final Map<String, dynamic> rawData; // collections, not metadata

  const BackupPreview({
    required this.appVersion,
    required this.createdAt,
    this.createdByUid,
    required this.tenantId,
    required this.scope,
    required this.routeIds,
    required this.counts,
    required this.checksumOk,
    required this.rawData,
  });

  int get totalRecords => counts.values.fold(0, (a, b) => a + b);
}

/// A backup file saved in the app's documents directory.
class LocalBackupFile {
  final File file;
  final DateTime modifiedAt;

  const LocalBackupFile({required this.file, required this.modifiedAt});

  String get name =>
      file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last;

  bool isStoredIn(Directory directory) =>
      file.absolute.parent.path.toLowerCase() ==
      directory.absolute.path.toLowerCase();
}

enum BackupDestination {
  userExport,
  googleDrive;

  bool get savesLocalCopy => this == BackupDestination.userExport;
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class DatabaseBackupNotifier extends Notifier<void> {
  bool _autoBackupInProgress = false;

  @override
  void build() {}

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── Preferences ───────────────────────────────────────────────────────────

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<UserModel> _requireBackupAdministrator({
    bool automatic = false,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null ||
        !user.active ||
        !user.canCreateWorkspaceBackup ||
        (automatic && !user.canRunAutomaticWorkspaceBackup)) {
      throw StateError('An active workspace administrator is required');
    }
    return user;
  }

  String _scopeSegment(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  Future<String> _scopedPreferenceKey(String key) async {
    final user = await ref.read(authUserProvider.future);
    final userId = user?.id ?? 'signed-out';
    final tenantId = TenantScope.normalize(user?.tenantId) ?? 'no-workspace';
    return '${key}_${_scopeSegment(tenantId)}_${_scopeSegment(userId)}';
  }

  String _securePassphraseKey(String tenantId, String userId) =>
      'backup_passphrase_${_scopeSegment(tenantId)}_${_scopeSegment(userId)}';

  Future<bool> getAutoEnabled() async {
    final key = await _scopedPreferenceKey(_kAutoEnabled);
    return (await _prefs).getBool(key) ?? false;
  }

  Future<int> getIntervalMinutes() async {
    final prefs = await _prefs;
    final key = await _scopedPreferenceKey(_kIntervalMinutes);
    final storedMinutes = prefs.getInt(key);
    if (storedMinutes != null) return storedMinutes;
    final legacyKey = await _scopedPreferenceKey(_kLegacyIntervalDays);
    final migratedMinutes = (prefs.getInt(legacyKey) ?? 7) * 24 * 60;
    await prefs.setInt(key, migratedMinutes);
    return migratedMinutes;
  }

  Future<DateTime?> getLastBackupAt() async {
    final key = await _scopedPreferenceKey(_kLastBackupMs);
    final ms = (await _prefs).getInt(key);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<DateTime?> getLastDriveBackupAt() async {
    final key = await _scopedPreferenceKey(_kLastDriveBackupMs);
    final ms = (await _prefs).getInt(key);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<DateTime?> getLastRestoreAt() async {
    final key = await _scopedPreferenceKey(_kLastRestoreMs);
    final ms = (await _prefs).getInt(key);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<String?> getLastRestoreBy() async {
    final key = await _scopedPreferenceKey(_kLastRestoreBy);
    return (await _prefs).getString(key);
  }

  Future<void> setAutoEnabled(bool value) async {
    await _requireBackupAdministrator(automatic: true);
    if (value && (kIsWeb || !GoogleDriveBackupService.isConfigured)) {
      throw StateError('Automatic Google Drive backup is not configured');
    }
    final key = await _scopedPreferenceKey(_kAutoEnabled);
    await (await _prefs).setBool(key, value);
  }

  Future<void> setIntervalMinutes(int minutes) async {
    await _requireBackupAdministrator(automatic: true);
    if (minutes < 15) {
      throw ArgumentError('Backup interval must be >= 15 minutes');
    }
    final key = await _scopedPreferenceKey(_kIntervalMinutes);
    await (await _prefs).setInt(key, minutes);
  }

  Future<void> rememberAutoBackupPassphrase(String passphrase) async {
    if (kIsWeb) {
      throw StateError(
        'Automatic encrypted backup is available on Android only',
      );
    }
    if (passphrase.trim().length < 12) {
      throw ArgumentError(
        'Backup passphrase must contain at least 12 characters',
      );
    }
    final user = await _requireBackupAdministrator(automatic: true);
    if (!GoogleDriveBackupService.isConfigured) {
      throw StateError('Google Drive OAuth is not configured for this build');
    }
    final tenantId = TenantScope.normalize(user.tenantId);
    if (tenantId == null) {
      throw StateError(
        'Select an active workspace before enabling auto-backup',
      );
    }
    await _backupSecretStorage.write(
      key: _securePassphraseKey(tenantId, user.id),
      value: passphrase,
    );
  }

  Future<void> clearAutoBackupPassphrase() async {
    final user = await _requireBackupAdministrator(automatic: true);
    final tenantId = TenantScope.normalize(user.tenantId);
    if (tenantId == null || kIsWeb) return;
    await _backupSecretStorage.delete(
      key: _securePassphraseKey(tenantId, user.id),
    );
  }

  Future<void> _recordBackupNow() async {
    final key = await _scopedPreferenceKey(_kLastBackupMs);
    await (await _prefs).setInt(key, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _recordDriveBackupNow() async {
    final key = await _scopedPreferenceKey(_kLastDriveBackupMs);
    await (await _prefs).setInt(key, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _recordRestoreNow(UserModel user, String byName) async {
    final prefs = await _prefs;
    final restoreAtKey = await _scopedPreferenceKey(_kLastRestoreMs);
    final restoreByKey = await _scopedPreferenceKey(_kLastRestoreBy);
    await prefs.setInt(restoreAtKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(restoreByKey, byName);
    if (!user.isAdmin) return;
    // Persist to Firestore so all admin devices see the restore event.
    // P1-12 FIX: Use per-tenant settings doc ID instead of hardcoded 'global'
    final currentUser = await ref.read(authUserProvider.future);
    final settingsDocId = _settingsDocumentIdForCurrentUser(currentUser);
    await _db.collection(Collections.settings).doc(settingsDocId).set({
      'last_restore_at': Timestamp.now(),
      'last_restore_by': byName,
      'updated_at': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  // ─── Local file storage ────────────────────────────────────────────────────

  Future<Directory> _backupDir({
    required String tenantId,
    required String creatorUid,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}/backups/${_scopeSegment(tenantId)}/${_scopeSegment(creatorUid)}',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Lists all local backups, newest first.
  Future<List<LocalBackupFile>> listLocalBackups({
    required String tenantId,
    required String creatorUid,
  }) async {
    final normalizedTenantId = TenantScope.normalize(tenantId);
    final normalizedUid = creatorUid.trim();
    if (normalizedTenantId == null || normalizedUid.isEmpty) return const [];
    final dir = await _backupDir(
      tenantId: normalizedTenantId,
      creatorUid: normalizedUid,
    );
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.shoesbackup') || f.path.endsWith('.json'),
            )
            .map(
              (f) => LocalBackupFile(file: f, modifiedAt: f.lastModifiedSync()),
            )
            .toList()
          ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  Future<void> deleteLocalBackup(
    LocalBackupFile backup, {
    required String tenantId,
    required String creatorUid,
  }) async {
    final user = await _requireBackupAdministrator();
    final normalizedTenantId = TenantScope.normalize(tenantId);
    final normalizedCreatorUid = creatorUid.trim();
    if (normalizedTenantId == null ||
        normalizedTenantId != TenantScope.normalize(user.tenantId) ||
        normalizedCreatorUid != user.id) {
      throw StateError('Local backup is outside the signed-in user scope');
    }
    if (!backup.file.path.endsWith('.shoesbackup') &&
        !backup.file.path.endsWith('.json')) {
      throw StateError('Unsupported local backup file type');
    }
    final directory = await _backupDir(
      tenantId: normalizedTenantId,
      creatorUid: normalizedCreatorUid,
    );
    if (!backup.isStoredIn(directory)) {
      throw StateError('Local backup is outside the permitted folder');
    }
    if (!await backup.file.exists()) {
      throw StateError('Local backup no longer exists');
    }
    await backup.file.delete();
  }

  Future<String> _saveToLocal(
    Uint8List bytes, {
    required String tenantId,
    required String creatorUid,
    required String fileName,
  }) async {
    final dir = await _backupDir(tenantId: tenantId, creatorUid: creatorUid);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ─── Checksum ──────────────────────────────────────────────────────────────

  /// Recursively sorts map keys so JSON encoding is deterministic.
  dynamic _sorted(dynamic v) {
    if (v is Map) {
      final sorted = SplayTreeMap<String, dynamic>.from(
        (v as Map<String, dynamic>).map((k, val) => MapEntry(k, _sorted(val))),
      );
      return sorted;
    }
    if (v is List) return v.map(_sorted).toList();
    return v;
  }

  /// SHA-256 hex digest over the sorted JSON encoding of [data].
  String _checksum(Map<String, dynamic> data) {
    final sorted = _sorted(data) as Map<String, dynamic>;
    final bytes = utf8.encode(jsonEncode(sorted));
    return sha256.convert(bytes).toString();
  }

  // ─── Firestore serialisation ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _readCollection(
    String path,
    UserModel currentUser,
    String? tenantScopeId,
  ) async {
    final result = <Map<String, dynamic>>[];
    final queries = <Query<Map<String, dynamic>>>[];
    final baseQuery = TenantScope.applyToQuery(
      _db.collection(path),
      tenantId: tenantScopeId,
    );
    if (currentUser.isSeller &&
        (path == Collections.shops ||
            path == Collections.transactions ||
            path == Collections.invoices)) {
      final routeIds = currentUser.assignedRouteIds;
      if (routeIds.isEmpty) return result;
      for (var offset = 0; offset < routeIds.length; offset += 30) {
        final end = (offset + 30).clamp(0, routeIds.length);
        queries.add(
          baseQuery.where('route_id', whereIn: routeIds.sublist(offset, end)),
        );
      }
    } else {
      final query = !currentUser.isSeller
          ? baseQuery
          : switch (path) {
              Collections.sellerInventory ||
              Collections.inventoryTransactions => baseQuery.where(
                'seller_id',
                isEqualTo: currentUser.id,
              ),
              Collections.routes => baseQuery.where(
                'assigned_seller_ids',
                arrayContains: currentUser.id,
              ),
              _ => baseQuery,
            };
      queries.add(query);
    }

    final seenIds = <String>{};
    for (final initialQuery in queries) {
      final query = initialQuery.orderBy(FieldPath.documentId).limit(500);
      QueryDocumentSnapshot<Map<String, dynamic>>? lastVisible;
      while (true) {
        final pageQuery = lastVisible == null
            ? query
            : query.startAfterDocument(lastVisible);
        final snap = await pageQuery.get();
        for (final document in snap.docs) {
          if (!seenIds.add(document.id)) continue;
          final documentData = document.data();
          if (path == Collections.users) {
            const safeProfileFields = {
              'tenant_id',
              'role',
              'email',
              'display_name',
              'phone',
              'active',
              'assigned_route_ids',
              'assigned_route_names',
              'email_verified',
              'created_at',
              'updated_at',
            };
            result.add({
              '__id': document.id,
              ..._sanitize({
                    for (final entry in documentData.entries)
                      if (safeProfileFields.contains(entry.key))
                        entry.key: entry.value,
                  })
                  as Map<String, dynamic>,
            });
          } else {
            result.add({
              '__id': document.id,
              ..._sanitize(documentData) as Map<String, dynamic>,
            });
          }
        }
        if (snap.docs.length < 500) break;
        lastVisible = snap.docs.last;
      }
    }
    return result;
  }

  dynamic _sanitize(dynamic value) {
    if (value is Timestamp) {
      return {
        '__type': 'Timestamp',
        's': value.seconds,
        'ns': value.nanoseconds,
      };
    }
    if (value is Map<String, dynamic>) {
      return value.map((k, v) => MapEntry(k, _sanitize(v)));
    }
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }

  dynamic _restoreTypes(dynamic value) {
    if (value is Map<String, dynamic>) {
      if (value['__type'] == 'Timestamp') {
        return Timestamp(value['s'] as int, value['ns'] as int);
      }
      return value.map((k, v) => MapEntry(k, _restoreTypes(v)));
    }
    if (value is List) return value.map(_restoreTypes).toList();
    return value;
  }

  // ─── Firestore write helpers ───────────────────────────────────────────────

  Future<int> _writeCollection(
    String path,
    List<dynamic> docs, {
    bool merge = false,
  }) async {
    for (var i = 0; i < docs.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400 > docs.length) ? docs.length : i + 400;
      for (var j = i; j < end; j++) {
        final doc = docs[j] as Map<String, dynamic>;
        final id = doc['__id'] as String;
        final data = Map<String, dynamic>.from(doc)..remove('__id');
        final restored = _restoreTypes(data) as Map<String, dynamic>;
        final reference = _db.collection(path).doc(id);
        if (merge) {
          batch.set(reference, restored, SetOptions(merge: true));
        } else {
          batch.set(reference, restored);
        }
      }
      await batch.commit();
    }
    return docs.length;
  }

  Future<int> _writePlatformUsers(
    List<dynamic> docs, {
    required UserModel actor,
    required String tenantId,
  }) async {
    for (var start = 0; start < docs.length; start += 100) {
      final batch = _db.batch();
      final end = (start + 100).clamp(0, docs.length);
      for (var index = start; index < end; index++) {
        final raw = Map<String, dynamic>.from(docs[index] as Map);
        final id = raw.remove('__id') as String;
        final data = _restoreTypes(raw) as Map<String, dynamic>;
        if (!TenantScope.matchesTenant(data, tenantId)) {
          throw StateError('Backup contains a user from another workspace');
        }
        final role = (data['role'] as String? ?? '')
            .trim()
            .toLowerCase()
            .replaceAll('-', '_');
        if (role == 'super_admin' || role == 'superadmin') {
          throw StateError('Platform super-admin profiles cannot be restored');
        }
        if (role == 'seller' &&
            (data['assigned_route_ids'] as List<dynamic>? ?? const [])
                .isEmpty) {
          throw StateError('A seller profile must have an assigned route');
        }

        final reference = _db.collection(Collections.users).doc(id);
        final existing = await reference.get();
        if (!existing.exists) data['created_by'] = actor.id;
        batch.set(reference, data, SetOptions(merge: true));
      }
      await batch.commit();
    }
    return docs.length;
  }

  Future<int> _deleteObsoleteTenantDocuments(
    String path,
    List<dynamic> docs,
    String tenantId,
  ) async {
    final replacementIds = <String>{
      for (final raw in docs) (raw as Map<String, dynamic>)['__id'] as String,
    };

    final existing = await fetchAllQueryDocuments(
      TenantScope.applyToQuery(
        _db.collection(path),
        tenantId: tenantId,
      ).orderBy(FieldPath.documentId),
    );
    final obsolete = existing
        .where((document) => !replacementIds.contains(document.id))
        .toList();
    for (var i = 0; i < obsolete.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400).clamp(0, obsolete.length);
      for (final document in obsolete.sublist(i, end)) {
        batch.delete(document.reference);
      }
      await batch.commit();
    }
    return obsolete.length;
  }

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Creates a backup of [selected] collections.
  ///
  /// Saves a copy to the app documents directory (for in-app restore) and
  /// returns the bytes so the caller can share them via the OS share sheet.
  Future<
    ({
      Uint8List bytes,
      String localPath,
      String fileName,
      String tenantId,
      String checksum,
      String scope,
      List<String> routeIds,
    })
  >
  createBackup({
    required Set<String> selected,
    required String encryptionPassword,
    required BackupDestination destination,
    String? tenantIdOverride,
  }) async {
    final adminUser = await _requireBackupAdministrator();
    final backupScope = BackupScopePolicy.scopeFor(adminUser.role);
    final allowedCollections = BackupScopePolicy.collectionsFor(adminUser.role);
    if (selected.isEmpty || !allowedCollections.containsAll(selected)) {
      throw ArgumentError('Selected collections are not allowed for this role');
    }
    final tenantScopeId = BackupScopePolicy.requireSelectedWorkspace(
      activeWorkspaceId: adminUser.tenantId,
      requestedWorkspaceId: tenantIdOverride,
    );
    final data = <String, dynamic>{};
    final counts = <String, int>{};

    Future<void> read(String key, String collPath) async {
      final docs = await _readCollection(collPath, adminUser, tenantScopeId);
      data[key] = docs;
      counts[key] = docs.length;
    }

    if (backupScope == BackupScope.platformMetadata) {
      if (selected.contains('workspaces')) {
        final workspace = await _db
            .collection(Collections.tenants)
            .doc(tenantScopeId)
            .get();
        if (!workspace.exists) {
          throw StateError('The selected workspace no longer exists');
        }
        data['workspaces'] = [
          {
            '__id': workspace.id,
            ..._sanitize(workspace.data()!) as Map<String, dynamic>,
          },
        ];
        counts['workspaces'] = 1;
      }
      if (selected.contains('users')) {
        await read('users', Collections.users);
        final workspaceUsers = (data['users'] as List<dynamic>).where((
          document,
        ) {
          final role =
              (document as Map<String, dynamic>)['role'] as String? ?? '';
          return !BackupScopePolicy.isPlatformRole(role);
        }).toList();
        data['users'] = workspaceUsers;
        counts['users'] = workspaceUsers.length;
      }
    } else {
      if (selected.contains('routes')) await read('routes', Collections.routes);
      if (selected.contains('shops')) await read('shops', Collections.shops);
      if (selected.contains('products')) {
        await read('products', Collections.products);
        await read('product_variants', Collections.productVariants);
      }
      if (selected.contains('inventory')) {
        await read('seller_inventory', Collections.sellerInventory);
        await read('inventory_transactions', Collections.inventoryTransactions);
      }
      if (selected.contains('transactions')) {
        await read('transactions', Collections.transactions);
      }
      if (selected.contains('invoices')) {
        await read('invoices', Collections.invoices);
      }
      if (selected.contains('settings')) {
        await read('settings', Collections.settings);
      }
    }

    // Compute checksum BEFORE wrapping in metadata.
    final checksum = _checksum(data);

    final payload = <String, dynamic>{
      'metadata': {
        'app': 'ShoesERP',
        'schema_version': 2,
        'app_version': AppBrand.versionDisplay,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'created_by_uid': adminUser.id,
        'tenant_id': tenantScopeId,
        'scope': BackupScopePolicy.archiveScopeFor(adminUser.role),
        'route_ids': const <String>[],
        'record_counts': counts,
        'checksum': checksum,
      },
      ...data,
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final plainBytes = Uint8List.fromList(utf8.encode(jsonStr));
    final bytes = await BackupCipher.encrypt(
      clearBytes: plainBytes,
      passphrase: encryptionPassword,
    );

    final createdAt = DateTime.now().toUtc();
    final fileName =
        'shoesERP_backup_${createdAt.year}${createdAt.month.toString().padLeft(2, '0')}${createdAt.day.toString().padLeft(2, '0')}_${createdAt.hour.toString().padLeft(2, '0')}${createdAt.minute.toString().padLeft(2, '0')}${createdAt.second.toString().padLeft(2, '0')}_${createdAt.microsecond.toString().padLeft(6, '0')}.shoesbackup';
    final localPath = kIsWeb || !destination.savesLocalCopy
        ? ''
        : await _saveToLocal(
            bytes,
            tenantId: tenantScopeId,
            creatorUid: adminUser.id,
            fileName: fileName,
          );
    if (destination.savesLocalCopy) await _recordBackupNow();
    return (
      bytes: bytes,
      localPath: localPath,
      fileName: fileName,
      tenantId: tenantScopeId,
      checksum: checksum,
      scope: BackupScopePolicy.archiveScopeFor(adminUser.role),
      routeIds: const <String>[],
    );
  }

  Future<GoogleDriveBackupFile> uploadBackupToDrive({
    required Uint8List bytes,
    required String fileName,
    required String encryptionPassword,
    String? tenantIdOverride,
  }) async {
    final user = await _requireBackupAdministrator();
    final clearBytes = await BackupCipher.decrypt(
      archiveBytes: bytes,
      passphrase: encryptionPassword,
    );
    final preview = verifyBackup(clearBytes);
    final tenantId = BackupScopePolicy.requireSelectedWorkspace(
      activeWorkspaceId: user.tenantId,
      requestedWorkspaceId: tenantIdOverride,
    );
    if (preview.tenantId != tenantId) {
      throw StateError(
        'Backup workspace does not match the selected workspace',
      );
    }
    if (preview.scope != BackupScopePolicy.archiveScopeFor(user.role)) {
      throw StateError('Backup content does not match this account role');
    }
    final checksum = preview.rawData.isEmpty ? '' : _checksum(preview.rawData);
    final uploaded = await GoogleDriveBackupService.upload(
      bytes: bytes,
      fileName: fileName,
      tenantId: tenantId,
      createdBy: user.id,
      checksum: checksum,
      scope: preview.scope,
      routeIds: const <String>[],
      formatVersion: BackupCipher.formatVersion,
    );
    await _recordDriveBackupNow();
    return uploaded;
  }

  Future<List<GoogleDriveBackupFile>> listDriveBackups({
    String? tenantIdOverride,
  }) async {
    final user = await _requireBackupAdministrator();
    final tenantId = BackupScopePolicy.requireSelectedWorkspace(
      activeWorkspaceId: user.tenantId,
      requestedWorkspaceId: tenantIdOverride,
    );
    return GoogleDriveBackupService.list(
      tenantId: tenantId,
      scope: BackupScopePolicy.archiveScopeFor(user.role),
      createdBy: null,
    );
  }

  Future<Uint8List> downloadDriveBackup(
    String fileId, {
    String? tenantIdOverride,
  }) async {
    final user = await _requireBackupAdministrator();
    final tenantId = BackupScopePolicy.requireSelectedWorkspace(
      activeWorkspaceId: user.tenantId,
      requestedWorkspaceId: tenantIdOverride,
    );
    return GoogleDriveBackupService.download(
      fileId: fileId,
      tenantId: tenantId,
      scope: BackupScopePolicy.archiveScopeFor(user.role),
      createdBy: null,
    );
  }

  Future<void> deleteDriveBackup(
    String fileId, {
    String? tenantIdOverride,
  }) async {
    final user = await _requireBackupAdministrator();
    final tenantId = BackupScopePolicy.requireSelectedWorkspace(
      activeWorkspaceId: user.tenantId,
      requestedWorkspaceId: tenantIdOverride,
    );
    await GoogleDriveBackupService.delete(
      fileId: fileId,
      tenantId: tenantId,
      scope: BackupScopePolicy.archiveScopeFor(user.role),
    );
  }

  /// Parses and integrity-checks a backup file.
  ///
  /// Returns a [BackupPreview] for presenting to the admin before restore.
  /// Throws [FormatException] if the file cannot be parsed.
  BackupPreview verifyBackup(Uint8List bytes) {
    final dynamic parsed = jsonDecode(utf8.decode(bytes));
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup file — not a JSON object');
    }
    final metadata = parsed['metadata'] as Map<String, dynamic>?;
    if (metadata == null) {
      throw const FormatException('Missing metadata section in backup file');
    }

    final storedChecksum = metadata['checksum'] as String?;
    final data = Map<String, dynamic>.from(parsed)..remove('metadata');

    bool checksumOk = false;
    if (storedChecksum != null) {
      checksumOk = (_checksum(data) == storedChecksum);
    }

    final rawCounts =
        (metadata['record_counts'] as Map<String, dynamic>?) ?? {};
    final counts = rawCounts.map((k, v) => MapEntry(k, (v as num).toInt()));

    return BackupPreview(
      appVersion: metadata['app_version'] as String? ?? '?',
      createdAt: metadata['created_at'] as String? ?? '?',
      createdByUid: metadata['created_by_uid'] as String?,
      tenantId: metadata['tenant_id'] as String? ?? TenantScope.globalTenantId,
      scope: metadata['scope'] as String? ?? 'unknown',
      routeIds: (metadata['route_ids'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      counts: counts,
      checksumOk: checksumOk,
      rawData: data,
    );
  }

  Future<BackupPreview> decryptAndVerifyBackup({
    required Uint8List archiveBytes,
    required String passphrase,
  }) async {
    final clearBytes = await BackupCipher.decrypt(
      archiveBytes: archiveBytes,
      passphrase: passphrase,
    );
    return verifyBackup(clearBytes);
  }

  /// Executes a restore from a verified [BackupPreview].
  ///
  /// ONLY call after the admin has confirmed via preview + password dialog.
  /// Returns the total number of documents restored.
  Future<int> restoreFromBackup(
    BackupPreview preview, {
    required String adminName,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active || !user.canRestoreWorkspaceBackup) {
      throw StateError('An active user is required for restore');
    }
    if (!preview.checksumOk) {
      throw const FormatException('Backup checksum verification failed');
    }
    final currentTenantId = TenantScope.normalize(user.tenantId);
    if (preview.tenantId == TenantScope.globalTenantId) {
      throw StateError('A concrete workspace is required for full restore');
    }
    if (currentTenantId == null || preview.tenantId != currentTenantId) {
      throw StateError(
        'Select the backup workspace as the active support workspace before restoring',
      );
    }

    if (user.isSuperAdmin && preview.scope == 'platform_metadata') {
      const allowed = BackupScopePolicy.platformMetadataCollections;
      if (preview.rawData.keys.any((key) => !allowed.contains(key))) {
        throw StateError(
          'Platform backups may contain only workspace metadata and users',
        );
      }
      for (final docs in preview.rawData.values) {
        if (docs is! List) {
          throw StateError('Platform backup collection data must be a list');
        }
        for (final rawDoc in docs) {
          if (rawDoc is! Map<String, dynamic>) {
            throw StateError('Platform backup contains an invalid record');
          }
          final documentId = rawDoc['__id'];
          if (documentId is! String || documentId.trim().isEmpty) {
            throw StateError('Platform backup contains a record without an ID');
          }
          if (!TenantScope.matchesTenant(rawDoc, preview.tenantId)) {
            throw StateError('Platform backup contains another workspace');
          }
        }
      }

      var restored = 0;
      final workspaces = preview.rawData['workspaces'];
      if (workspaces != null) {
        final workspaceDocs = workspaces as List<dynamic>;
        if (workspaceDocs.any(
          (doc) => (doc as Map<String, dynamic>)['__id'] != preview.tenantId,
        )) {
          throw StateError('Platform backup workspace ID does not match');
        }
        restored += await _writeCollection(
          Collections.tenants,
          workspaceDocs,
          merge: true,
        );
      }
      final users = preview.rawData['users'];
      if (users != null) {
        restored += await _writePlatformUsers(
          users as List<dynamic>,
          actor: user,
          tenantId: preview.tenantId,
        );
      }
      await _recordRestoreNow(user, adminName);
      return restored;
    }

    if (preview.scope != 'workspace' ||
        (!user.isTenantAdmin && !user.isSuperAdmin)) {
      throw StateError(
        'Workspace data restore is not permitted for this backup',
      );
    }
    const allowedWorkspaceCollections =
        BackupScopePolicy.workspaceBusinessCollections;
    if (preview.rawData.keys.any(
      (key) => !allowedWorkspaceCollections.contains(key),
    )) {
      throw StateError('Workspace backup contains unsupported collections');
    }
    for (final docs in preview.rawData.values) {
      if (docs is! List) {
        throw StateError('Workspace backup collection data must be a list');
      }
      for (final rawDoc in docs) {
        if (rawDoc is! Map<String, dynamic>) {
          throw StateError('Workspace backup contains an invalid record');
        }
        final documentId = rawDoc['__id'];
        if (documentId is! String || documentId.trim().isEmpty) {
          throw StateError('Workspace backup contains a record without an ID');
        }
        if (!TenantScope.matchesTenant(rawDoc, preview.tenantId)) {
          throw StateError('Backup contains another workspace');
        }
      }
    }

    const collectionMap = {
      'routes': Collections.routes,
      'shops': Collections.shops,
      'products': Collections.products,
      'product_variants': Collections.productVariants,
      'seller_inventory': Collections.sellerInventory,
      'inventory_transactions': Collections.inventoryTransactions,
      'transactions': Collections.transactions,
      'invoices': Collections.invoices,
      'settings': Collections.settings,
    };

    var totalRestored = 0;
    for (final entry in collectionMap.entries) {
      final docs = preview.rawData[entry.key];
      if (docs == null) continue;
      totalRestored += await _writeCollection(
        entry.value,
        docs as List<dynamic>,
      );
    }
    if (user.canPruneWorkspaceBackup) {
      for (final entry in collectionMap.entries) {
        final docs = preview.rawData[entry.key];
        if (docs == null) continue;
        await _deleteObsoleteTenantDocuments(
          entry.value,
          docs as List<dynamic>,
          preview.tenantId,
        );
      }
    }

    await _recordRestoreNow(user, adminName);
    return totalRestored;
  }

  /// Checks whether an auto-backup is due; if so, runs it silently.
  /// Returns null if the interval has not elapsed or auto is disabled.
  Future<
    ({
      Uint8List bytes,
      String localPath,
      String fileName,
      String tenantId,
      String checksum,
      String scope,
      List<String> routeIds,
    })?
  >
  checkAndAutoBackup() async {
    if (_autoBackupInProgress) return null;
    _autoBackupInProgress = true;
    try {
      final user = await ref.read(authUserProvider.future);
      if (user == null ||
          !user.active ||
          !user.canRunAutomaticWorkspaceBackup ||
          kIsWeb ||
          !GoogleDriveBackupService.isConfigured) {
        return null;
      }
      final enabled = await getAutoEnabled();
      if (!enabled) return null;
      final tenantId = TenantScope.normalize(user.tenantId);
      if (tenantId == null) return null;
      final passphrase = await _backupSecretStorage.read(
        key: _securePassphraseKey(tenantId, user.id),
      );
      if (passphrase == null || passphrase.length < 12) return null;
      final intervalMinutes = await getIntervalMinutes();
      final lastAt = await getLastDriveBackupAt();
      if (lastAt != null &&
          DateTime.now().difference(lastAt).inMinutes < intervalMinutes) {
        return null;
      }
      final result = await createBackup(
        selected: BackupScopePolicy.collectionsFor(user.role),
        encryptionPassword: passphrase,
        destination: BackupDestination.googleDrive,
        tenantIdOverride: tenantId,
      );
      await uploadBackupToDrive(
        bytes: result.bytes,
        fileName: result.fileName,
        tenantIdOverride: result.tenantId,
        encryptionPassword: passphrase,
      );
      return result;
    } finally {
      _autoBackupInProgress = false;
    }
  }
}

final databaseBackupProvider = NotifierProvider<DatabaseBackupNotifier, void>(
  DatabaseBackupNotifier.new,
);
