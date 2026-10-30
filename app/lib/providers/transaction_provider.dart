import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/collections.dart';
import '../core/utils/backup_scope_policy.dart';
import '../core/utils/financial_minor_unit_migration.dart';
import '../core/utils/formatters.dart';
import '../core/utils/financial_amount_policy.dart';
import '../core/utils/firestore_pagination.dart';
import '../core/utils/notification_writer.dart';
import '../core/utils/tenant_scope.dart';
import '../models/transaction_model.dart';
import 'auth_provider.dart';

// =============================================================================
// TransactionProvider — all shop ledger writes go through this notifier.
//
// ARCHITECTURE:
//   Shops are stored in the 'customers' Firestore collection (legacy name).
//   All balance updates reference Collections.customers / Collections.shops.
//
// TWO FINANCIAL PATHWAYS:
//   1. SALE WITH STOCK → InvoiceNotifier.createSaleInvoice() (in invoice_provider.dart)
//      - Atomically creates invoice + cash_out tx + optional cash_in tx + stock deduction
//      - cash_out tx has invoice_id field linking it back to the invoice
//   2. CASH COLLECTION (debt only, no new sale) → TransactionNotifier.create()
//      - type: 'cash_in', no items, no invoice created
//      - Reduces shop.balance atomically
//      - Called from ShopDetailScreen quick-cash panel
//
// BALANCE DELTA CONVENTION:
//   cash_out  → balance += amount  (shop owes more)
//   cash_in   → balance -= amount  (shop owes less)
//   return    → balance -= amount  (goods returned, owes less)
//   write_off → balance zeroed by ShopNotifier.markAsBadDebt() directly
//
// SOFT DELETE (DI-01): never hard-delete transactions; set deleted=true + reverse balance.
// =============================================================================

const _shopTransactionsLiveLimit = 150;
const _shopsAnalyticsTransactionsLimit = 500;

final _logger = Logger();

String transactionIdempotencyDocumentId({
  required String tenantId,
  required String idempotencyKey,
}) => const Uuid().v5(
  Namespace.url.value,
  '$tenantId:standalone-transaction:$idempotencyKey',
);

bool _isCustomerLedgerEntry(Map<String, dynamic> data) =>
    data['deleted'] != true && data['voided'] != true;

List<TransactionModel> sortTransactionsForExport(
  List<TransactionModel> transactions,
) {
  final sorted = List<TransactionModel>.from(transactions);
  sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return sorted;
}

final shopTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) {
        return Stream.value(const <TransactionModel>[]);
      }
      final profileReady = ref.watch(
        authUserProvider.select((s) => s.hasValue && s.value != null),
      );
      if (!profileReady) return const Stream.empty();
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .where('shop_id', isEqualTo: normalizedShopId)
          .orderBy('created_at', descending: true)
          .limit(_shopTransactionsLiveLimit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => _isCustomerLedgerEntry(d.data()))
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final shopTransactionsFallbackProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, shopId) {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) {
        return Stream.value(const <TransactionModel>[]);
      }
      final profileReady = ref.watch(
        authUserProvider.select((s) => s.hasValue && s.value != null),
      );
      if (!profileReady) return const Stream.empty();

      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final base = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );

      return base
          .where('shop_id', isEqualTo: normalizedShopId)
          .limit(_shopTransactionsLiveLimit)
          .snapshots()
          .map(
            (snap) =>
                snap.docs
                    .where((d) => _isCustomerLedgerEntry(d.data()))
                    .map((d) => TransactionModel.fromJson(d.data(), d.id))
                    .toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          );
    });

final allTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      // Admin-only unfiltered query: guard to prevent PERMISSION_DENIED.
      // Use select() so heartbeat writes to last_active do NOT restart the stream.
      final isAdmin = ref.watch(
        authUserProvider.select(
          (s) => s.value?.canManageOperationalData ?? false,
        ),
      );
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      if (!isAdmin) return const Stream.empty();
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// Shop analytics need actual ledger flow, not just current balances.
/// Admins see all transactions; sellers see all transactions on their route.
final shopsAnalyticsTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      ref.keepAlive();
      // Use select() with a string key (not List<String>) so Riverpod's ==
      // check correctly identifies no-change on heartbeat writes to last_active.
      // List<String> uses reference equality — a new UserModel snapshot always
      // produces a new List object, which would look like "changed" and restart
      // this Firestore stream every 5 minutes, causing analytics strip flicker.
      final (isAdmin, isSeller, routeKey) = ref.watch(
        authUserProvider.select((s) {
          final u = s.value;
          if (u == null) return (false, false, '');
          if (u.canManageOperationalData) return (true, false, '');
          if (!u.isSeller || u.assignedRouteIds.isEmpty) {
            return (false, false, '');
          }
          final sorted = List<String>.from(u.assignedRouteIds)..sort();
          return (false, true, sorted.join(','));
        }),
      );
      if (!isAdmin && (!isSeller || routeKey.isEmpty)) {
        return Stream.value(const <TransactionModel>[]);
      }

      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final collection = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );

      if (isAdmin) {
        return collection
            .orderBy('created_at', descending: true)
            .limit(_shopsAnalyticsTransactionsLimit)
            .snapshots()
            .map(
              (snap) => snap.docs
                  .where((d) => _isCustomerLedgerEntry(d.data()))
                  .map((d) => TransactionModel.fromJson(d.data(), d.id))
                  .toList(),
            );
      }

      final routeIds = routeKey.split(',');
      return collection
          .where('route_id', whereIn: routeIds)
          .orderBy('created_at', descending: true)
          .limit(_shopsAnalyticsTransactionsLimit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => _isCustomerLedgerEntry(d.data()))
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

final pendingEditRequestsProvider =
    StreamProvider.autoDispose<List<TransactionModel>>((ref) {
      // Use select() so heartbeat writes to last_active do NOT restart the stream.
      final isAdmin = ref.watch(
        authUserProvider.select((s) => s.value?.isAdmin ?? false),
      );
      if (!isAdmin) {
        return Stream.value(const <TransactionModel>[]);
      }
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .where('edit_request_pending', isEqualTo: true)
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// Seller-scoped: transactions created by this seller.
final sellerTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, sellerId) {
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      return query
          .where('created_by', isEqualTo: sellerId)
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((d) => d.data()['deleted'] != true)
                .map((d) => TransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// One-shot shop transactions for export (PDF/Excel). NOT autoDispose:
/// callers use ref.read(provider.future) which doesn't subscribe, so
/// autoDispose would destroy the provider mid-Firestore-query → StateError.
/// Callers must ref.invalidate() before reading for fresh data.
final shopTransactionsExportProvider =
    FutureProvider.family<List<TransactionModel>, String>((ref, shopId) async {
      final normalizedShopId = shopId.trim();
      if (normalizedShopId.isEmpty) return const <TransactionModel>[];

      final tenantId = await ref
          .read(authUserProvider.future)
          .then((user) => TenantScope.normalize(user?.tenantId));
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      final docs = await fetchAllQueryDocuments(
        query
            .where('shop_id', isEqualTo: normalizedShopId)
            .orderBy('created_at', descending: true),
      );

      final txs = docs
          .where((d) => _isCustomerLedgerEntry(d.data()))
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();

      return sortTransactionsForExport(txs);
    });

/// All transactions for a specific route — used by multi-shop PDF export.
/// NOT autoDispose: callers use ref.read(provider.future) which doesn't
/// subscribe — autoDispose would destroy the provider mid-query → StateError.
/// Callers must ref.invalidate() before reading for fresh data.
final routeTransactionsExportProvider =
    FutureProvider.family<List<TransactionModel>, String>((ref, routeId) async {
      final normalizedId = routeId.trim();
      if (normalizedId.isEmpty) return const <TransactionModel>[];
      // Use .future to await first auth emission instead of reading a
      // potentially-null .value while the StreamProvider is still loading.
      final user = await ref.read(authUserProvider.future);
      if (user == null) return const <TransactionModel>[];
      if (!user.canManageOperationalData) {
        if (!user.isSeller || !user.assignedRouteIds.contains(normalizedId)) {
          return const <TransactionModel>[];
        }
      }
      final tenantId = TenantScope.normalize(user.tenantId);
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      final docs = await fetchAllQueryDocuments(
        query
            .where('route_id', isEqualTo: normalizedId)
            .orderBy('created_at', descending: true),
      );
      final txs = docs
          .where((d) => _isCustomerLedgerEntry(d.data()))
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();
      return sortTransactionsForExport(txs);
    });

/// All transactions across all routes — admin-only bulk export.
/// NOT autoDispose: see routeTransactionsExportProvider comment.
final allTransactionsExportProvider = FutureProvider<List<TransactionModel>>((
  ref,
) async {
  // Use .future to await first auth emission instead of reading a
  // potentially-null .value while the StreamProvider is still loading.
  final user = await ref.read(authUserProvider.future);
  if (user == null || !user.canManageOperationalData) {
    return const <TransactionModel>[];
  }
  final tenantId = TenantScope.normalize(user.tenantId);
  final query = TenantScope.applyToQuery(
    FirebaseFirestore.instance.collection(Collections.transactions),
    tenantId: tenantId,
  );
  final docs = await fetchAllQueryDocuments(
    query.orderBy('created_at', descending: true),
  );
  final txs = docs
      .where((d) => _isCustomerLedgerEntry(d.data()))
      .map((d) => TransactionModel.fromJson(d.data(), d.id))
      .toList();
  return sortTransactionsForExport(txs);
});

/// One-shot transactions for a specific seller — used by seller report PDF.
/// NOT autoDispose: callers use ref.read(provider.future) which doesn't
/// subscribe — autoDispose would destroy the provider mid-query → StateError.
/// Callers must ref.invalidate() before reading to ensure fresh data.
final sellerTransactionsExportProvider =
    FutureProvider.family<List<TransactionModel>, String>((
      ref,
      sellerId,
    ) async {
      final normalizedId = sellerId.trim();
      if (normalizedId.isEmpty) return const <TransactionModel>[];
      final user = await ref.read(authUserProvider.future);
      if (user == null ||
          !user.active ||
          (!user.canManageOperationalData &&
              (!user.isSeller || user.id != normalizedId))) {
        return const <TransactionModel>[];
      }
      final tenantId = TenantScope.normalize(user.tenantId);
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.transactions),
        tenantId: tenantId,
      );
      final docs = await fetchAllQueryDocuments(
        query
            .where('created_by', isEqualTo: normalizedId)
            .orderBy('created_at', descending: true),
      );
      final txs = docs
          .where((d) => _isCustomerLedgerEntry(d.data()))
          .map((d) => TransactionModel.fromJson(d.data(), d.id))
          .toList();
      return sortTransactionsForExport(txs);
    });

class TransactionNotifier extends AsyncNotifier<void> {
  bool _writeInFlight = false;

  Future<String> _currentTenantId() async {
    final user = await ref.read(authUserProvider.future);
    return TenantScope.requireTenant(user?.tenantId);
  }

  @override
  Future<void> build() async {}

  Future<void> _runWriteGuard(Future<void> Function() op) async {
    if (_writeInFlight) {
      throw StateError('Another transaction write is already in progress.');
    }
    _writeInFlight = true;
    try {
      await op();
    } finally {
      _writeInFlight = false;
    }
  }

  Future<bool> _createWithIdempotencyKey({
    required FirebaseFirestore db,
    required String tenantId,
    required String idempotencyKey,
    required String shopId,
    required String shopName,
    required String routeId,
    required String type,
    required double amount,
    required String? description,
    required String? saleType,
    required String createdBy,
    required Timestamp? transactionDate,
  }) async {
    final txRef = db
        .collection(Collections.transactions)
        .doc(
          transactionIdempotencyDocumentId(
            tenantId: tenantId,
            idempotencyKey: idempotencyKey,
          ),
        );
    final shopRef = db.collection(Collections.customers).doc(shopId);
    final createdAt = transactionDate ?? Timestamp.now();
    final balanceDelta = type == 'cash_out' ? amount : -amount;
    return db.runTransaction<bool>((transaction) async {
      final existingSnapshot = await transaction.get(txRef);
      if (existingSnapshot.exists) {
        final existing = existingSnapshot.data()!;
        final existingCreatedAt = existing['created_at'] as Timestamp?;
        final matchesRequest =
            existing['tenant_id'] == tenantId &&
            existing['idempotency_key'] == idempotencyKey &&
            existing['shop_id'] == shopId &&
            existing['shop_name'] == shopName &&
            existing['route_id'] == routeId &&
            existing['type'] == type &&
            existing['sale_type'] == saleType &&
            existing['amount'] == amount &&
            existing['description'] == description &&
            existing['created_by'] == createdBy &&
            existingCreatedAt?.microsecondsSinceEpoch ==
                createdAt.microsecondsSinceEpoch;
        if (matchesRequest) return false;
        throw StateError('Transaction idempotency key was reused');
      }

      final shopSnapshot = await transaction.get(shopRef);
      final shopData = shopSnapshot.data();
      if (!shopSnapshot.exists ||
          shopData == null ||
          !TenantScope.matchesTenant(shopData, tenantId) ||
          shopData['route_id'] != routeId) {
        throw StateError(
          'Transaction shop is outside the active workspace and route.',
        );
      }
      if (type == TransactionModel.typeCashOut &&
          (shopData['active'] == false || shopData['deleted'] == true)) {
        throw StateError(
          'Archived shops cannot accept new cash-out transactions.',
        );
      }

      transaction.set(
        txRef,
        FinancialMinorUnitMigration.withMinorUnits('transactions', {
          'shop_id': shopId,
          'customer_id': shopId,
          'shop_name': shopName,
          'route_id': routeId,
          'tenant_id': tenantId,
          'type': type,
          'sale_type': saleType,
          'amount': amount,
          'description': description,
          'items': const <Map<String, dynamic>>[],
          'created_by': createdBy,
          'created_at': createdAt,
          'deleted': false,
          'idempotency_key': idempotencyKey,
        }),
      );
      transaction.update(shopRef, {
        'balance': FieldValue.increment(balanceDelta),
        'financial_minor_units':
            FinancialMinorUnitMigration.companionsAfterUpdate(
              'shops',
              shopData,
              {
                'balance':
                    (shopData['balance'] as num).toDouble() + balanceDelta,
                'last_transaction_amount': amount,
              },
            ),
        'updated_at': Timestamp.now(),
        'last_transaction_at': createdAt,
        'last_transaction_type': type,
        'last_transaction_amount': amount,
        'last_transaction_id': txRef.id,
      });
      return true;
    });
  }

  void _stageTransactionUpdate({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> transactionRef,
    required DocumentReference<Map<String, dynamic>> shopRef,
    required Map<String, dynamic> shopData,
    required String txId,
    required Map<String, dynamic> sourceData,
    required String actorId,
    required String reason,
    required double oldAmount,
    required String oldType,
    required double newAmount,
    required String newType,
    String? description,
    String? saleType,
    Timestamp? transactionDate,
    Map<String, dynamic> extraTxFields = const <String, dynamic>{},
  }) {
    if (!AppFormatters.hasAtMostTwoDecimalPlaces(newAmount) ||
        newAmount > FinancialAmountPolicy.maximumAmount) {
      throw ArgumentError(
        'Transaction amounts must be within the supported two-decimal limit',
      );
    }
    final historyEntry = <String, dynamic>{
      'previous_amount': oldAmount,
      'previous_type': oldType,
      'previous_created_at': sourceData['created_at'],
      'previous_description': sourceData['description'] ?? '',
      'changed_by': actorId,
      'reason': reason.trim(),
      'changed_at': Timestamp.now(),
    };
    final updatePayload = <String, dynamic>{
      'amount': newAmount,
      'type': newType,
      'edit_history': FieldValue.arrayUnion([historyEntry]),
      ...extraTxFields,
      'updated_at': Timestamp.now(),
    };
    if (description != null) updatePayload['description'] = description;
    if (saleType != null) updatePayload['sale_type'] = saleType;
    if (transactionDate != null) updatePayload['created_at'] = transactionDate;

    final oldEditHistory = sourceData['edit_history'];
    if (oldEditHistory != null && oldEditHistory is! List) {
      throw StateError('Transaction edit history is malformed');
    }
    final updatedTransactionData = Map<String, dynamic>.from(sourceData)
      ..remove(FinancialMinorUnitMigration.companionField)
      ..['amount'] = newAmount
      ..['type'] = newType
      ..['edit_history'] = [...?oldEditHistory as List?, historyEntry];
    if (extraTxFields.containsKey('edit_request_new_amount')) {
      updatedTransactionData.remove('edit_request_new_amount');
    }
    updatePayload['financial_minor_units'] =
        FinancialMinorUnitMigration.withMinorUnits(
          'transactions',
          updatedTransactionData,
        )['financial_minor_units'];

    transaction.update(transactionRef, updatePayload);

    final oldDelta = oldType == TransactionModel.typeCashOut
        ? oldAmount
        : -oldAmount;
    final newDelta = newType == TransactionModel.typeCashOut
        ? newAmount
        : -newAmount;
    final netChange = -oldDelta + newDelta;
    final shopUpdate = <String, dynamic>{
      'balance': FieldValue.increment(netChange),
      'financial_minor_units':
          FinancialMinorUnitMigration.companionsAfterUpdate('shops', shopData, {
            'balance': (shopData['balance'] as num).toDouble() + netChange,
            if (shopData['last_transaction_id'] == txId)
              'last_transaction_amount': newAmount,
          }),
      'last_balance_correction_transaction_id': txId,
      'updated_at': Timestamp.now(),
    };
    if (shopData['last_transaction_id'] == txId) {
      shopUpdate.addAll({
        'last_transaction_at':
            transactionDate ?? sourceData['created_at'] ?? Timestamp.now(),
        'last_transaction_type': newType,
        'last_transaction_amount': newAmount,
      });
    }
    transaction.update(shopRef, shopUpdate);
  }

  /// Creates a transaction and updates shop balance atomically.
  /// For cash_out with items, also deducts stock from variants.
  Future<void> create({
    required String shopId,
    required String shopName,
    required String routeId,
    required String type,
    required double amount,
    String? description,
    String? saleType,
    List<TransactionItem> items = const [],
    required String createdBy,
    Timestamp? transactionDate,
    required String idempotencyKey,
  }) async {
    await _runWriteGuard(() async {
      final normalizedCreatedBy = createdBy.trim();
      if (normalizedCreatedBy.isEmpty) {
        throw ArgumentError('createdBy must not be empty');
      }
      if (!TransactionModel.isStandaloneCashType(type)) {
        throw ArgumentError(
          'Standalone transactions must be cash_in or cash_out.',
        );
      }
      if (amount <= 0) {
        throw ArgumentError('Transaction amount must be greater than 0');
      }
      if (!AppFormatters.hasAtMostTwoDecimalPlaces(amount) ||
          amount > FinancialAmountPolicy.maximumAmount) {
        throw ArgumentError(
          'Transaction amounts must be within the supported two-decimal limit',
        );
      }
      if (shopId.trim().isEmpty) {
        throw ArgumentError('shopId must not be empty');
      }
      if (routeId.trim().isEmpty) {
        throw ArgumentError('routeId must not be empty');
      }
      if (items.isNotEmpty) {
        throw ArgumentError(
          'Stock sales must use the invoice creation workflow.',
        );
      }

      final db = FirebaseFirestore.instance;
      final tenantId = await _currentTenantId();
      final normalizedKey = idempotencyKey.trim();
      if (normalizedKey.isEmpty) {
        throw ArgumentError('idempotencyKey must not be empty');
      }
      final txId = transactionIdempotencyDocumentId(
        tenantId: tenantId,
        idempotencyKey: normalizedKey,
      );
      final created = await _createWithIdempotencyKey(
        db: db,
        tenantId: tenantId,
        idempotencyKey: normalizedKey,
        shopId: shopId,
        shopName: shopName,
        routeId: routeId,
        type: type,
        amount: amount,
        description: description,
        saleType: saleType,
        createdBy: normalizedCreatedBy,
        transactionDate: transactionDate,
      );
      if (!created) return;

      try {
        final appUser = await ref.read(authUserProvider.future);
        if (appUser != null && appUser.isSeller) {
          await writeSellerNotification(
            db: db,
            data: buildSellerNotification(
              sourceType: 'transaction',
              sourceId: txId,
              sellerId: normalizedCreatedBy,
              sellerName: appUser.displayName,
              tenantId: tenantId,
              shopId: shopId,
              shopName: shopName,
              routeId: routeId,
              amount: amount,
              transactionType: type,
            ),
          );
        }
      } catch (error, stackTrace) {
        _logger.w(
          'Best-effort transaction notification write failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  /// Restores seller-owned cash ledger entries for one currently assigned
  /// route. Existing transaction IDs are left untouched, and each imported
  /// entry updates the shop balance in the same Firestore transaction.
  Future<int> restoreSellerRouteTransactions({
    required String routeId,
    required List<Map<String, dynamic>> documents,
  }) async {
    final user = await ref.read(authUserProvider.future);
    if (user == null || !user.active || !user.isSeller) {
      throw StateError('Seller privileges required for route restore');
    }
    final normalizedRouteId = routeId.trim();
    final assignedRouteIds = BackupScopePolicy.routeIdsFor(
      user.assignedRouteIds,
    );
    if (normalizedRouteId.isEmpty ||
        !assignedRouteIds.contains(normalizedRouteId)) {
      throw StateError('Route access has been revoked');
    }
    final tenantId = TenantScope.requireTenant(user.tenantId);
    var restored = 0;
    final eligibleDocuments =
        documents
            .where(
              (document) => BackupScopePolicy.isSellerTransactionRestorable(
                document: document,
                sellerId: user.id,
                routeId: normalizedRouteId,
                tenantId: tenantId,
                assignedRouteIds: assignedRouteIds,
              ),
            )
            .toList()
          ..sort((a, b) {
            final dateOrder = (a['created_at'] as Timestamp).compareTo(
              b['created_at'] as Timestamp,
            );
            if (dateOrder != 0) return dateOrder;
            return (a['__id'] as String).compareTo(b['__id'] as String);
          });

    await _runWriteGuard(() async {
      final db = FirebaseFirestore.instance;
      for (final raw in eligibleDocuments) {
        final txId = (raw['__id'] as String?)?.trim() ?? '';
        final shopId = (raw['shop_id'] as String?)?.trim() ?? '';
        final txRef = db.collection(Collections.transactions).doc(txId);
        final shopRef = db.collection(Collections.customers).doc(shopId);
        final imported = await db.runTransaction<bool>((transaction) async {
          final existing = await transaction.get(txRef);
          if (existing.exists) return false;
          final shop = await transaction.get(shopRef);
          final shopData = shop.data();
          if (!shop.exists ||
              shopData == null ||
              !TenantScope.matchesTenant(shopData, tenantId) ||
              shopData['route_id'] != normalizedRouteId ||
              shopData['balance'] is! num) {
            return false;
          }
          final model = TransactionModel.fromJson(raw, txId);
          final lastTransactionAt = shopData['last_transaction_at'];
          transaction.set(txRef, {
            ...model.toJson(),
            'customer_id': model.shopId,
            'tenant_id': tenantId,
            'deleted': false,
          });
          final balanceAfter =
              (shopData['balance'] as num).toDouble() + model.balanceImpact;
          final shopUpdate = <String, dynamic>{
            'balance': FieldValue.increment(model.balanceImpact),
            'updated_at': Timestamp.now(),
          };
          if (lastTransactionAt is! Timestamp ||
              lastTransactionAt.compareTo(model.createdAt) <= 0) {
            shopUpdate.addAll({
              'last_transaction_at': model.createdAt,
              'last_transaction_type': model.type,
              'last_transaction_amount': model.amount,
              'last_transaction_id': txId,
            });
          }
          shopUpdate['financial_minor_units'] =
              FinancialMinorUnitMigration.companionsAfterUpdate(
                'shops',
                shopData,
                {
                  'balance': balanceAfter,
                  if (shopUpdate.containsKey('last_transaction_amount'))
                    'last_transaction_amount': model.amount,
                },
              );
          transaction.update(shopRef, shopUpdate);
          return true;
        });
        if (imported) restored++;
      }
    });
    return restored;
  }

  /// Seller-safe annotation: updates only the [description] field.
  /// Firestore rules restrict seller updates to ['description', 'updated_at'].
  /// Admins should use [updateTransaction] for financial field changes.
  Future<void> updateTransactionNote({
    required String txId,
    required String? description,
    String updatedBy = '',
  }) async {
    if (txId.trim().isEmpty) {
      throw ArgumentError('txId must not be empty');
    }
    await FirebaseFirestore.instance
        .collection(Collections.transactions)
        .doc(txId)
        .update({
          if (description != null && description.isNotEmpty)
            'description': description.trim()
          else
            'description': FieldValue.delete(),
          if (updatedBy.trim().isNotEmpty) 'updated_by': updatedBy.trim(),
          'updated_at': Timestamp.now(),
        });
  }

  /// Soft-deletes a transaction (sets deleted=true) and reverses its balance
  /// impact on the customer. Preserves audit trail.
  Future<void> deleteTransaction({
    required String txId,
    required String? shopId,
    required double amount,
    required String type,
    required String deletedBy,
  }) async {
    if (txId.trim().isEmpty) {
      throw ArgumentError('txId must not be empty');
    }
    await _runWriteGuard(() async {
      final user = await ref.read(authUserProvider.future);
      if (user == null || !user.active || !user.isAdmin) {
        throw StateError('Active workspace administrator access is required.');
      }
      final tenantId = TenantScope.requireTenant(user.tenantId);
      if (deletedBy.trim() != user.id) {
        throw StateError('Transaction deletion actor does not match.');
      }

      final db = FirebaseFirestore.instance;
      final transactionRef = db
          .collection(Collections.transactions)
          .doc(txId.trim());
      await db.runTransaction<void>((transaction) async {
        final snapshot = await transaction.get(transactionRef);
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          throw StateError('Transaction not found.');
        }
        if (data['tenant_id'] != tenantId) {
          throw StateError('Transaction is outside the active workspace.');
        }
        if (data['deleted'] == true) return;
        if ((data['invoice_id'] as String?)?.trim().isNotEmpty == true) {
          throw StateError(
            'Invoice-linked transactions cannot be deleted. Void or credit the invoice instead.',
          );
        }
        final storedType = data['type'] as String? ?? '';
        final storedAmount = (data['amount'] as num?)?.toDouble() ?? 0;
        if ((storedType != TransactionModel.typeCashIn &&
                storedType != TransactionModel.typeCashOut) ||
            storedAmount <= 0 ||
            storedAmount != amount ||
            storedType != type) {
          throw StateError(
            'Transaction changed or is not deletable. Refresh and retry.',
          );
        }
        final storedShopId = (data['shop_id'] as String?)?.trim() ?? '';
        if (storedShopId.isEmpty || storedShopId != shopId?.trim()) {
          throw StateError('Transaction shop does not match.');
        }
        final shopRef = db.collection(Collections.customers).doc(storedShopId);
        final notificationRef = db
            .collection(Collections.notifications)
            .doc(
              sellerNotificationDocumentId(
                sourceType: 'transaction',
                sourceId: txId.trim(),
              ),
            );
        final shopSnapshot = await transaction.get(shopRef);
        final notificationSnapshot = await transaction.get(notificationRef);
        final shopData = shopSnapshot.data();
        if (!shopSnapshot.exists ||
            shopData == null ||
            shopData['tenant_id'] != tenantId) {
          throw StateError('Transaction shop is outside the active workspace.');
        }

        final reversalDelta = storedType == TransactionModel.typeCashOut
            ? -storedAmount
            : storedAmount;
        transaction.update(transactionRef, {
          'deleted': true,
          'deleted_at': FieldValue.serverTimestamp(),
          'deleted_by': user.id,
          'updated_at': FieldValue.serverTimestamp(),
        });
        final notificationRetirement = {
          'source_deleted': true,
          'source_deleted_at': FieldValue.serverTimestamp(),
        };
        if (notificationSnapshot.exists) {
          transaction.update(notificationRef, notificationRetirement);
        } else {
          transaction.set(notificationRef, {
            'tenant_id': tenantId,
            'type': 'transaction',
            'ref_id': txId.trim(),
            'shop_id': storedShopId,
            ...notificationRetirement,
          });
        }
        final shopUpdate = <String, dynamic>{
          'balance': FieldValue.increment(reversalDelta),
          'updated_at': FieldValue.serverTimestamp(),
          'last_balance_correction_transaction_id': txId.trim(),
        };
        final shopFinancialUpdates = <String, dynamic>{
          'balance': (shopData['balance'] as num).toDouble() + reversalDelta,
        };
        if (shopData['last_transaction_id'] == txId.trim()) {
          shopUpdate.addAll({
            'last_transaction_at': FieldValue.delete(),
            'last_transaction_type': FieldValue.delete(),
            'last_transaction_amount': FieldValue.delete(),
            'last_transaction_id': FieldValue.delete(),
          });
          shopFinancialUpdates['last_transaction_amount'] = null;
        }
        shopUpdate['financial_minor_units'] =
            FinancialMinorUnitMigration.companionsAfterUpdate(
              'shops',
              shopData,
              shopFinancialUpdates,
            );
        transaction.update(shopRef, shopUpdate);
      });
    });
  }

  /// Updates a transaction and adjusts customer balance for the change.
  Future<void> updateTransaction({
    required String txId,
    required String? shopId,
    required double oldAmount,
    required String oldType,
    required double newAmount,
    required String newType,
    required String reason,
    String? description,
    String? saleType,
    Timestamp? transactionDate,
  }) async {
    await _runWriteGuard(() async {
      if (txId.trim().isEmpty) {
        throw ArgumentError('txId must not be empty');
      }
      if (newAmount <= 0) {
        throw ArgumentError('newAmount must be greater than 0');
      }
      if (!AppFormatters.hasAtMostTwoDecimalPlaces(newAmount) ||
          newAmount > FinancialAmountPolicy.maximumAmount) {
        throw ArgumentError(
          'Transaction amounts must be within the supported two-decimal limit',
        );
      }
      if (!TransactionModel.isStandaloneCashType(newType) ||
          !TransactionModel.isStandaloneCashType(oldType)) {
        throw ArgumentError(
          'Only standalone cash_in/cash_out transactions can be corrected.',
        );
      }
      if (reason.trim().length < 10) {
        throw ArgumentError('Correction reason must be at least 10 characters');
      }

      final user = await ref.read(authUserProvider.future);
      if (user == null || !user.active || !user.isAdmin) {
        throw StateError('Admin privileges required');
      }
      final tenantId = TenantScope.requireTenant(user.tenantId);
      final db = FirebaseFirestore.instance;
      final transactionRef = db
          .collection(Collections.transactions)
          .doc(txId.trim());
      await db
          .runTransaction((transaction) async {
            final transactionSnapshot = await transaction.get(transactionRef);
            if (!transactionSnapshot.exists) {
              throw StateError('Transaction not found');
            }
            final sourceData = transactionSnapshot.data()!;
            if (sourceData['tenant_id'] != tenantId) {
              throw StateError('Transaction is outside the active workspace');
            }
            final linkedInvoiceId = (sourceData['invoice_id'] as String?)
                ?.trim();
            if (linkedInvoiceId != null && linkedInvoiceId.isNotEmpty) {
              throw StateError(
                'Invoice-linked transactions cannot be edited. Void or credit the invoice instead.',
              );
            }
            if (sourceData['deleted'] == true) {
              throw StateError('Deleted transactions cannot be corrected.');
            }
            final storedAmount =
                (sourceData['amount'] as num?)?.toDouble() ?? 0;
            final storedType = (sourceData['type'] as String?) ?? '';
            if (storedAmount != oldAmount ||
                storedType != oldType ||
                !TransactionModel.isStandaloneCashType(storedType)) {
              throw StateError(
                'Transaction changed or is not editable. Refresh and retry.',
              );
            }
            final storedShopId =
                (sourceData['shop_id'] as String?)?.trim() ?? '';
            if (storedShopId.isEmpty ||
                (shopId?.trim().isNotEmpty == true &&
                    shopId!.trim() != storedShopId)) {
              throw StateError('Transaction shop does not match.');
            }
            final shopRef = db
                .collection(Collections.customers)
                .doc(storedShopId);
            final shopSnapshot = await transaction.get(shopRef);
            final shopData = shopSnapshot.data();
            if (!shopSnapshot.exists ||
                shopData == null ||
                shopData['tenant_id'] != tenantId ||
                shopData['balance'] is! num) {
              throw StateError(
                'Transaction shop is outside the active workspace.',
              );
            }

            _stageTransactionUpdate(
              transaction: transaction,
              transactionRef: transactionRef,
              shopRef: shopRef,
              shopData: shopData,
              txId: txId.trim(),
              sourceData: sourceData,
              actorId: user.id,
              reason: reason,
              oldAmount: storedAmount,
              oldType: storedType,
              newAmount: newAmount,
              newType: newType,
              description: description,
              saleType: saleType,
              transactionDate: transactionDate,
            );
          })
          .timeout(const Duration(seconds: 20));
    });
  }

  /// Seller edits cash_in/cash_out transactions.
  /// Returns true when applied immediately, false when submitted for approval.
  Future<bool> sellerEditTransaction({
    required String txId,
    required String sellerId,
    required double newAmount,
    required String newType,
    String? description,
    String? saleType,
    Timestamp? transactionDate,
  }) async {
    if (txId.trim().isEmpty) throw ArgumentError('txId must not be empty');
    if (sellerId.trim().isEmpty) {
      throw ArgumentError('sellerId must not be empty');
    }
    if (newAmount <= 0) {
      throw ArgumentError('newAmount must be greater than 0');
    }
    if (!AppFormatters.hasAtMostTwoDecimalPlaces(newAmount) ||
        newAmount > FinancialAmountPolicy.maximumAmount) {
      throw ArgumentError(
        'Transaction amounts must be within the supported two-decimal limit',
      );
    }
    if (newType != 'cash_in' && newType != 'cash_out') {
      throw ArgumentError('Seller can edit only cash_in/cash_out transactions');
    }

    final db = FirebaseFirestore.instance;
    final txRef = db.collection(Collections.transactions).doc(txId);
    final txDoc = await txRef.get();
    if (!txDoc.exists) throw StateError('Transaction not found');
    final data = txDoc.data()!;

    final createdBy = (data['created_by'] as String?)?.trim() ?? '';
    if (createdBy != sellerId.trim()) {
      throw StateError('Seller can edit only own transactions');
    }

    final linkedInvoiceId = (data['invoice_id'] as String?)?.trim() ?? '';
    if (linkedInvoiceId.isNotEmpty) {
      throw StateError(
        'Cannot edit a transaction that is linked to invoice '
        '$linkedInvoiceId. Void the invoice to make corrections.',
      );
    }

    final alreadyPending = data['edit_request_pending'] as bool? ?? false;
    if (alreadyPending) {
      throw StateError(
        'An edit request is already pending for this transaction. '
        'Wait for admin review before submitting another.',
      );
    }

    final oldType = (data['type'] as String?) ?? 'cash_out';
    if (oldType != 'cash_in' && oldType != 'cash_out') {
      throw StateError('Only cash_in/cash_out transactions can be edited');
    }

    final currentUser = await ref.read(authUserProvider.future);
    final tenantId = TenantScope.requireTenant(currentUser?.tenantId);
    final settingsDoc = await db
        .collection(Collections.settings)
        .doc(tenantId)
        .get();
    final allowEditRequests =
        (settingsDoc.data()?['allow_seller_edit_requests'] as bool?) ??
        (settingsDoc
                .data()?['require_admin_approval_for_seller_transaction_edits']
            as bool?) ??
        false;

    if (allowEditRequests) {
      final financialMinorUnits =
          FinancialMinorUnitMigration.companionsAfterUpdate(
            'transactions',
            data,
            {'edit_request_new_amount': newAmount},
          );
      await txRef
          .update({
            'edit_request_pending': true,
            'edit_request_status': 'pending',
            'edit_request_requested_by': sellerId.trim(),
            'edit_request_requested_at': Timestamp.now(),
            'edit_request_new_amount': newAmount,
            'financial_minor_units': financialMinorUnits,
            'edit_request_new_type': newType,
            'edit_request_new_description': description,
            'edit_request_new_sale_type': saleType,
            'edit_request_new_created_at': transactionDate,
            'updated_at': Timestamp.now(),
          })
          .timeout(const Duration(seconds: 20));
      return false;
    }

    final oldAmount = (data['amount'] as num?)?.toDouble() ?? 0;
    final oldCreatedAt = data['created_at'] as Timestamp?;
    final dateChanged =
        transactionDate != null &&
        oldCreatedAt?.millisecondsSinceEpoch !=
            transactionDate.millisecondsSinceEpoch;
    final oldSaleType = data['sale_type'] as String?;
    if (newAmount != oldAmount ||
        newType != oldType ||
        dateChanged ||
        (saleType != null && saleType != oldSaleType)) {
      throw StateError(
        'Sellers may only annotate transactions when admin approval is disabled',
      );
    }

    await txRef
        .update({
          'description': description?.trim().isNotEmpty == true
              ? description!.trim()
              : FieldValue.delete(),
          'updated_by': sellerId.trim(),
          'updated_at': Timestamp.now(),
        })
        .timeout(const Duration(seconds: 20));
    return true;
  }

  /// Admin review for seller-submitted transaction edit requests.
  Future<void> reviewSellerEditRequest({
    required String txId,
    required bool approved,
    required String reviewerId,
  }) async {
    if (txId.trim().isEmpty) throw ArgumentError('txId must not be empty');
    if (reviewerId.trim().isEmpty) {
      throw ArgumentError('reviewerId must not be empty');
    }

    final reviewer = await ref.read(authUserProvider.future);
    if (reviewer == null ||
        !reviewer.active ||
        !reviewer.isAdmin ||
        reviewer.id != reviewerId.trim()) {
      throw StateError('Admin privileges required');
    }

    final tenantId = TenantScope.requireTenant(reviewer.tenantId);
    final db = FirebaseFirestore.instance;
    final txRef = db.collection(Collections.transactions).doc(txId);
    await db
        .runTransaction((transaction) async {
          final txDoc = await transaction.get(txRef);
          if (!txDoc.exists) throw StateError('Transaction not found');
          final data = txDoc.data()!;
          if (data['tenant_id'] != tenantId) {
            throw StateError('Transaction is outside the active workspace.');
          }
          if (data['edit_request_pending'] != true) return;

          if (!approved) {
            transaction.update(txRef, {
              'edit_request_pending': false,
              'edit_request_status': 'rejected',
              'edit_request_reviewed_by': reviewer.id,
              'edit_request_reviewed_at': Timestamp.now(),
              'updated_at': Timestamp.now(),
            });
            return;
          }

          final oldType = (data['type'] as String?) ?? '';
          final newType = (data['edit_request_new_type'] as String?) ?? oldType;
          final oldAmount = (data['amount'] as num?)?.toDouble() ?? 0;
          final newAmount =
              (data['edit_request_new_amount'] as num?)?.toDouble() ??
              oldAmount;
          final shopId = (data['shop_id'] as String?)?.trim() ?? '';
          if (shopId.isEmpty ||
              !TransactionModel.isStandaloneCashType(oldType) ||
              !TransactionModel.isStandaloneCashType(newType) ||
              oldAmount <= 0 ||
              newAmount <= 0 ||
              !AppFormatters.hasAtMostTwoDecimalPlaces(newAmount) ||
              newAmount > FinancialAmountPolicy.maximumAmount ||
              (data['invoice_id'] as String?)?.trim().isNotEmpty == true) {
            throw StateError(
              'Transaction is not eligible for seller correction.',
            );
          }

          final shopRef = db.collection(Collections.customers).doc(shopId);
          final shopDoc = await transaction.get(shopRef);
          final shopData = shopDoc.data();
          if (!shopDoc.exists ||
              shopData == null ||
              shopData['tenant_id'] != tenantId ||
              shopData['balance'] is! num) {
            throw StateError(
              'Transaction shop is outside the active workspace.',
            );
          }

          _stageTransactionUpdate(
            transaction: transaction,
            transactionRef: txRef,
            shopRef: shopRef,
            shopData: shopData,
            txId: txId.trim(),
            sourceData: data,
            actorId: reviewer.id,
            reason: 'Approved seller transaction edit request',
            oldAmount: oldAmount,
            oldType: oldType,
            newAmount: newAmount,
            newType: newType,
            description: data['edit_request_new_description'] as String?,
            saleType: data['edit_request_new_sale_type'] as String?,
            transactionDate: data['edit_request_new_created_at'] as Timestamp?,
            extraTxFields: {
              'edit_request_pending': false,
              'edit_request_status': 'approved',
              'edit_request_reviewed_by': reviewer.id,
              'edit_request_reviewed_at': Timestamp.now(),
              'edit_request_new_amount': FieldValue.delete(),
              'edit_request_new_type': FieldValue.delete(),
              'edit_request_new_description': FieldValue.delete(),
              'edit_request_new_sale_type': FieldValue.delete(),
              'edit_request_new_created_at': FieldValue.delete(),
            },
          );
        })
        .timeout(const Duration(seconds: 20));
  }
}

final transactionNotifierProvider =
    AsyncNotifierProvider<TransactionNotifier, void>(TransactionNotifier.new);
