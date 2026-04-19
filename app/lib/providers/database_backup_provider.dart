import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_brand.dart';
import '../core/constants/collections.dart';
import 'auth_provider.dart';

// ─── SharedPreferences keys ──────────────────────────────────────────────────
const _kAutoEnabled = 'backup_auto_enabled';
const _kIntervalDays = 'backup_interval_days';
const _kLastBackupMs = 'backup_last_ms';
const _kLastRestoreMs = 'backup_last_restore_ms';
const _kLastRestoreBy = 'backup_last_restore_by';

// ─── Data classes ─────────────────────────────────────────────────────────────

/// Metadata parsed from a backup JSON file, shown to the admin before restore.
class BackupPreview {
  final String appVersion;
  final String createdAt;
  final String? createdByUid;
  final Map<String, int> counts;
  final bool checksumOk;
  final Map<String, dynamic> rawData; // collections, not metadata

  const BackupPreview({
    required this.appVersion,
    required this.createdAt,
    this.createdByUid,
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

  Future<bool> getAutoEnabled() async =>
      (await _prefs).getBool(_kAutoEnabled) ?? false;

  Future<int> getIntervalDays() async =>
      (await _prefs).getInt(_kIntervalDays) ?? 7;

  Future<DateTime?> getLastBackupAt() async {
    final ms = (await _prefs).getInt(_kLastBackupMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<DateTime?> getLastRestoreAt() async {
    final ms = (await _prefs).getInt(_kLastRestoreMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<String?> getLastRestoreBy() async =>
      (await _prefs).getString(_kLastRestoreBy);

  Future<void> setAutoEnabled(bool value) async =>
      (await _prefs).setBool(_kAutoEnabled, value);

  Future<void> setIntervalDays(int days) async =>
      (await _prefs).setInt(_kIntervalDays, days);

  Future<void> _recordBackupNow() async => (await _prefs).setInt(
    _kLastBackupMs,
    DateTime.now().millisecondsSinceEpoch,
  );

  Future<void> _recordRestoreNow(String byName) async {
    final prefs = await _prefs;
    await prefs.setInt(_kLastRestoreMs, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(_kLastRestoreBy, byName);
    // Persist to Firestore so all admin devices see the restore event.
    await _db.collection(Collections.settings).doc('global').set({
      'last_restore_at': Timestamp.now(),
      'last_restore_by': byName,
      'updated_at': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  // ─── Local file storage ────────────────────────────────────────────────────

  Future<Directory> _backupDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/backups');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Lists all local backups, newest first.
  Future<List<LocalBackupFile>> listLocalBackups() async {
    final dir = await _backupDir();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .map(
              (f) => LocalBackupFile(file: f, modifiedAt: f.lastModifiedSync()),
            )
            .toList()
          ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return files;
  }

  Future<String> _saveToLocal(Uint8List bytes) async {
    final dir = await _backupDir();
    final ts = DateTime.now().toUtc();
    final name =
        'shoesERP_backup_${ts.year}${_p(ts.month)}${_p(ts.day)}_${_p(ts.hour)}${_p(ts.minute)}${_p(ts.second)}.json';
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

  Future<List<Map<String, dynamic>>> _readCollection(String path) async {
    final result = <Map<String, dynamic>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastVisible;
    while (true) {
      Query<Map<String, dynamic>> q = _db
          .collection(path)
          .orderBy(FieldPath.documentId)
          .limit(500);
      if (lastVisible != null) q = q.startAfterDocument(lastVisible);
      final snap = await q.get();
      for (final d in snap.docs) {
        result.add({
          '__id': d.id,
          ..._sanitize(d.data()) as Map<String, dynamic>,
        });
      }
      if (snap.docs.length < 500) break;
      lastVisible = snap.docs.last;
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

  Future<int> _deleteCollection(String path) async {
    var deleted = 0;
    while (true) {
      final snap = await _db.collection(path).limit(400).get();
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

  Future<int> _writeCollection(String path, List<dynamic> docs) async {
    for (var i = 0; i < docs.length; i += 400) {
      final batch = _db.batch();
      final end = (i + 400 > docs.length) ? docs.length : i + 400;
      for (var j = i; j < end; j++) {
        final doc = docs[j] as Map<String, dynamic>;
        final id = doc['__id'] as String;
        final data = Map<String, dynamic>.from(doc)..remove('__id');
        final restored = _restoreTypes(data) as Map<String, dynamic>;
        batch.set(_db.collection(path).doc(id), restored);
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
  Future<({Uint8List bytes, String localPath})> createBackup({
    required Set<String> selected,
  }) async {
    final adminUser = ref.read(authUserProvider).value;
    final data = <String, dynamic>{};
    final counts = <String, int>{};

    Future<void> read(String key, String collPath) async {
      final docs = await _readCollection(collPath);
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

    // Compute checksum BEFORE wrapping in metadata.
    final checksum = _checksum(data);

    final payload = <String, dynamic>{
      'metadata': {
        'app': 'ShoesERP',
        'app_version': AppBrand.versionDisplay,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'created_by_uid': adminUser?.id ?? '',
        'record_counts': counts,
        'checksum': checksum,
      },
      ...data,
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    await _recordBackupNow();
    final localPath = await _saveToLocal(bytes);
    return (bytes: bytes, localPath: localPath);
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
  }) async {
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
      await _deleteCollection(entry.value);
      totalRestored += await _writeCollection(
        entry.value,
        docs as List<dynamic>,
      );
    }

    await _recordRestoreNow(adminName);
    return totalRestored;
  }

  /// Checks whether an auto-backup is due; if so, runs it silently.
  /// Returns null if the interval has not elapsed or auto is disabled.
  Future<({Uint8List bytes, String localPath})?> checkAndAutoBackup() async {
    final enabled = await getAutoEnabled();
    if (!enabled) return null;
    final intervalDays = await getIntervalDays();
    final lastAt = await getLastBackupAt();
    if (lastAt != null &&
        DateTime.now().difference(lastAt).inDays < intervalDays) {
      return null;
    }
    return createBackup(
      selected: const {
        'routes',
        'shops',
        'products',
        'inventory',
        'transactions',
        'invoices',
      },
    );
  }
}

final databaseBackupProvider = NotifierProvider<DatabaseBackupNotifier, void>(
  DatabaseBackupNotifier.new,
);
