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
import '../core/utils/tenant_scope.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';
import 'transaction_provider.dart';

// ─── SharedPreferences keys ──────────────────────────────────────────────────
const _kAutoEnabled = 'backup_auto_enabled';
const _kIntervalMinutes = 'backup_interval_minutes';
const _kLegacyIntervalDays = 'backup_interval_days';
const _kLastBackupMs = 'backup_last_ms';
const _kLastRestoreMs = 'backup_last_restore_ms';
const _kLastRestoreBy = 'backup_last_restore_by';
const _backupSecretStorage = FlutterSecureStorage();

// ─── Helper functions ────────────────────────────────────────────────────────

/// P1-12 FIX: Derive per-tenant settings doc ID from user profile.
/// Matches the pattern used in settings_provider.dart.
String _settingsDocumentIdForCurrentUser(UserModel? currentUser) {
  final tenantId = TenantScope.normalize(currentUser?.tenantId);
  return tenantId ?? TenantScope.globalTenantId;
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

  String get name => file.path.split(Platform.pathSeparator).last;
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class DatabaseBackupNotifier extends Notifier<void> {
  @override
  void build() {}

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─── Preferences ───────────────────────────────────────────────────────────

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

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
    final key = await _scopedPreferenceKey(_kAutoEnabled);
    await (await _prefs).setBool(key, value);
  }

  Future<void> setIntervalMinutes(int minutes) async {
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
    final user = await ref.read(authUserProvider.future);
    final tenantId = TenantScope.normalize(user?.tenantId);
    if (user == null || !user.active || !user.isAdmin || tenantId == null) {
      throw StateError('An active workspace administrator is required');
    }
    await _backupSecretStorage.write(
      key: _securePassphraseKey(tenantId, user.id),
      value: passphrase,
    );
  }

  Future<void> clearAutoBackupPassphrase() async {
    final user = await ref.read(authUserProvider.future);
    final tenantId = TenantScope.normalize(user?.tenantId);
    if (user == null || tenantId == null || kIsWeb) return;
    await _backupSecretStorage.delete(
      key: _securePassphraseKey(tenantId, user.id),
    );
  }

  Future<void> _recordBackupNow() async {
    final key = await _scopedPreferenceKey(_kLastBackupMs);
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

  Future<String> _saveToLocal(
    Uint8List bytes, {
    required String tenantId,
    required String creatorUid,
  }) async {
    final dir = await _backupDir(tenantId: tenantId, creatorUid: creatorUid);
    final ts = DateTime.now().toUtc();
    final name =
        'shoesERP_backup_${ts.year}${_p(ts.month)}${_p(ts.day)}_${_p(ts.hour)}${_p(ts.minute)}${_p(ts.second)}.shoesbackup';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  String _p(int n) => n.toString().padLeft(2, '0');

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

  Future<int> _deleteCollection(
    String path,
    UserModel user,
    String tenantScopeId,
  ) async {
    final activeTenantId = TenantScope.normalize(user.tenantId);
    if (!user.isSuperAdmin || activeTenantId != tenantScopeId) {
      throw StateError(
        'Full workspace replacement requires the active super-admin workspace',
      );
    }
    var deleted = 0;
    while (true) {
      final query = TenantScope.applyToQuery(
        _db.collection(path),
        tenantId: tenantScopeId,
      );
      final snap = await query.limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snap.docs.length;
    }
    return deleted;
  }

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

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Creates a backup of [selected] collections.
  ///
  /// Saves a copy to the app documents directory (for in-app restore) and
  /// returns the bytes so the caller can share them via the OS share sheet.
  Future<
    ({
      Uint8List bytes,
      String localPath,
      String tenantId,
      String checksum,
      String scope,
      List<String> routeIds,
    })
  >
  createBackup({
    required Set<String> selected,
    required String encryptionPassword,
    String? tenantIdOverride,
  }) async {
    final adminUser = await ref.read(authUserProvider.future);
    if (adminUser == null || !adminUser.active) {
      throw StateError('An active user is required to create a backup');
    }
    final ownTenantId = TenantScope.normalize(adminUser.tenantId);
    final requestedTenantId = TenantScope.normalize(tenantIdOverride);
    final tenantScopeId = adminUser.isSuperAdmin ? ownTenantId : ownTenantId;
    if (tenantScopeId == null) {
      throw StateError('Select an active workspace before creating a backup');
    }
    if (requestedTenantId != null && requestedTenantId != ownTenantId) {
      throw StateError('Backup workspace must match the active workspace');
    }
    final data = <String, dynamic>{};
    final counts = <String, int>{};

    Future<void> read(String key, String collPath) async {
      final docs = await _readCollection(collPath, adminUser, tenantScopeId);
      data[key] = docs;
      counts[key] = docs.length;
    }

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
    if (!adminUser.isSeller && selected.contains('users')) {
      await read('users', Collections.users);
    }
    if (!adminUser.isSeller && selected.contains('settings')) {
      await read('settings', Collections.settings);
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
        'scope': adminUser.isSeller ? 'seller_routes' : 'workspace',
        'route_ids': adminUser.isSeller
            ? List<String>.from(adminUser.assignedRouteIds)
            : const <String>[],
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

    await _recordBackupNow();
    final localPath = await _saveToLocal(
      bytes,
      tenantId: tenantScopeId,
      creatorUid: adminUser.id,
    );
    return (
      bytes: bytes,
      localPath: localPath,
      tenantId: tenantScopeId,
      checksum: checksum,
      scope: adminUser.isSeller ? 'seller_routes' : 'workspace',
      routeIds: adminUser.isSeller
          ? List<String>.from(adminUser.assignedRouteIds)
          : const <String>[],
    );
  }

  Future<GoogleDriveBackupFile> uploadBackupToDrive({
    required Uint8List bytes,
    required String fileName,
    required String encryptionPassword,
    String? tenantIdOverride,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active) {
      throw StateError('An active user is required for Google Drive backup');
    }
    final clearBytes = await BackupCipher.decrypt(
      archiveBytes: bytes,
      passphrase: encryptionPassword,
    );
    final preview = verifyBackup(clearBytes);
    final ownTenantId = TenantScope.normalize(user.tenantId);
    final tenantId = user.isSuperAdmin
        ? TenantScope.normalize(tenantIdOverride)
        : ownTenantId;
    if (tenantId == null) {
      throw StateError('Select a workspace before uploading a backup');
    }
    if (preview.tenantId != tenantId) {
      throw StateError(
        'Backup workspace does not match the selected workspace',
      );
    }
    final checksum = preview.rawData.isEmpty ? '' : _checksum(preview.rawData);
    return GoogleDriveBackupService.upload(
      bytes: bytes,
      fileName: fileName,
      tenantId: tenantId,
      createdBy: user.id,
      checksum: checksum,
      scope: user.isSeller ? 'seller_routes' : 'workspace',
      routeIds: user.isSeller ? user.assignedRouteIds : const <String>[],
      formatVersion: BackupCipher.formatVersion,
    );
  }

  Future<List<GoogleDriveBackupFile>> listDriveBackups({
    String? tenantIdOverride,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active) {
      throw StateError('An active user is required for Google Drive backup');
    }
    final tenantId = user.isSuperAdmin
        ? TenantScope.normalize(tenantIdOverride)
        : TenantScope.normalize(user.tenantId);
    if (tenantId == null) {
      throw StateError('Select a workspace before listing backups');
    }
    return GoogleDriveBackupService.list(
      tenantId: tenantId,
      createdBy: user.isSeller ? user.id : null,
    );
  }

  Future<Uint8List> downloadDriveBackup(
    String fileId, {
    String? tenantIdOverride,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active) {
      throw StateError('An active user is required for Google Drive restore');
    }
    final tenantId = user.isSuperAdmin
        ? TenantScope.normalize(tenantIdOverride)
        : TenantScope.normalize(user.tenantId);
    if (tenantId == null) {
      throw StateError('Select a workspace before downloading a backup');
    }
    return GoogleDriveBackupService.download(
      fileId: fileId,
      tenantId: tenantId,
      createdBy: user.isSeller ? user.id : null,
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

  /// Executes a restore from a verified [BackupPreview].
  ///
  /// ONLY call after the admin has confirmed via preview + password dialog.
  /// Returns the total number of documents restored.
  Future<int> restoreFromBackup(
    BackupPreview preview, {
    required String adminName,
    String? routeId,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active) {
      throw StateError('An active user is required for restore');
    }
    if (!preview.checksumOk) {
      throw const FormatException('Backup checksum verification failed');
    }
    final currentTenantId = TenantScope.normalize(user.tenantId);
    if (user.isSeller) {
      final selectedRouteId = routeId?.trim() ?? '';
      if (preview.scope != 'seller_routes' || selectedRouteId.isEmpty) {
        throw StateError('Seller restore requires a route-scoped backup');
      }
      if (!preview.routeIds.contains(selectedRouteId) ||
          !user.assignedRouteIds.contains(selectedRouteId)) {
        throw StateError('Route access has been revoked');
      }
      final rawTransactions = preview.rawData['transactions'];
      if (rawTransactions is! List) return 0;
      final documents = rawTransactions
          .whereType<Map<String, dynamic>>()
          .map((doc) => _restoreTypes(doc) as Map<String, dynamic>)
          .toList();
      final restored = await ref
          .read(transactionNotifierProvider.notifier)
          .restoreSellerRouteTransactions(
            routeId: selectedRouteId,
            documents: documents,
          );
      await _recordRestoreNow(
        user,
        user.displayName.trim().isNotEmpty ? user.displayName : adminName,
      );
      return restored;
    }
    if (!user.isSuperAdmin) {
      throw StateError(
        'Full workspace replacement requires a platform super-admin. '
        'Contact the platform administrator to request a restore.',
      );
    }
    if (preview.scope != 'workspace') {
      throw StateError('Full restore requires a workspace backup');
    }
    if (preview.tenantId == TenantScope.globalTenantId) {
      throw StateError('A concrete workspace is required for full restore');
    }
    if (currentTenantId == null || preview.tenantId != currentTenantId) {
      throw StateError(
        'Select the backup workspace as the active support workspace before restoring',
      );
    }
    for (final docs in preview.rawData.values) {
      if (docs is! List) continue;
      for (final rawDoc in docs) {
        if (rawDoc is Map<String, dynamic> &&
            !TenantScope.matchesTenant(rawDoc, preview.tenantId)) {
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
    };

    var totalRestored = 0;
    for (final entry in collectionMap.entries) {
      final docs = preview.rawData[entry.key];
      if (docs == null) continue;
      await _deleteCollection(entry.value, user, preview.tenantId);
      totalRestored += await _writeCollection(
        entry.value,
        docs as List<dynamic>,
      );
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
      String tenantId,
      String checksum,
      String scope,
      List<String> routeIds,
    })?
  >
  checkAndAutoBackup() async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active || kIsWeb) return null;
    final enabled = await getAutoEnabled();
    if (!enabled) return null;
    final tenantId = TenantScope.normalize(user.tenantId);
    if (tenantId == null) return null;
    final passphrase = await _backupSecretStorage.read(
      key: _securePassphraseKey(tenantId, user.id),
    );
    if (passphrase == null || passphrase.length < 12) return null;
    if (kIsWeb) return null;
    final intervalMinutes = await getIntervalMinutes();
    final lastAt = await getLastBackupAt();
    if (lastAt != null &&
        DateTime.now().difference(lastAt).inMinutes < intervalMinutes) {
      return null;
    }
    final result = await createBackup(
      selected: const {
        'routes',
        'shops',
        'products',
        'inventory',
        'transactions',
        'invoices',
        'users',
        'settings',
      },
      encryptionPassword: passphrase,
      tenantIdOverride: tenantId,
    );
    await uploadBackupToDrive(
      bytes: result.bytes,
      fileName: result.localPath.split(Platform.pathSeparator).last,
      tenantIdOverride: result.tenantId,
      encryptionPassword: passphrase,
    );
    return result;
  }
}

final databaseBackupProvider = NotifierProvider<DatabaseBackupNotifier, void>(
  DatabaseBackupNotifier.new,
);
