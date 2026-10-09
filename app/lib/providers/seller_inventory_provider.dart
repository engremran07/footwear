import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/role_utils.dart';
import '../core/utils/firestore_pagination.dart';
import '../core/utils/tenant_scope.dart';
import '../models/seller_inventory_model.dart';
import 'auth_provider.dart';

final sellerInventoryProvider = StreamProvider.autoDispose
    .family<List<SellerInventoryModel>, String>((ref, sellerId) {
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.sellerInventory),
        tenantId: tenantId,
      );
      return query
          .where('seller_id', isEqualTo: sellerId)
          .where('active', isEqualTo: true)
          .limit(500)
          .snapshots()
          .map((snap) {
            final inventory = snap.docs
                .map((d) => SellerInventoryModel.fromJson(d.data(), d.id))
                .toList();
            inventory.sort(
              (a, b) => a.variantName.toLowerCase().compareTo(
                b.variantName.toLowerCase(),
              ),
            );
            return inventory;
          });
    });

final sellerInventoryTotalPairsProvider =
    Provider.family<AsyncValue<int>, String>((ref, sellerId) {
      final itemsAsync = ref.watch(sellerInventoryProvider(sellerId));
      return itemsAsync.whenData(
        (items) =>
            items.fold<int>(0, (acc, item) => acc + item.quantityAvailable),
      );
    });

/// Streams ALL active seller-inventory items (admin use for reports).
/// Limit is 100 to keep free-tier Firestore reads within budget.
final adminAllSellerInventoryProvider =
    StreamProvider.autoDispose<List<SellerInventoryModel>>((ref) {
      // Use select() so heartbeat writes to last_active do NOT restart the stream.
      final isAdmin = ref.watch(
        authUserProvider.select((s) => s.value?.isAdmin ?? false),
      );
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      if (!isAdmin) return const Stream.empty();
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.sellerInventory),
        tenantId: tenantId,
      );
      return query.where('active', isEqualTo: true).limit(100).snapshots().map((
        snap,
      ) {
        final inventory = snap.docs
            .map((d) => SellerInventoryModel.fromJson(d.data(), d.id))
            .toList();
        inventory.sort(
          (a, b) => a.variantName.toLowerCase().compareTo(
            b.variantName.toLowerCase(),
          ),
        );
        return inventory;
      });
    });

/// One-shot active seller inventory for export (seller report PDF/Excel).
/// NOT autoDispose: callers use ref.read(provider.future); no listener →
/// autoDispose would destroy the provider mid-query → StateError.
/// Callers must ref.invalidate() before reading to ensure fresh data.
final sellerInventoryExportProvider =
    FutureProvider.family<List<SellerInventoryModel>, String>((
      ref,
      sellerId,
    ) async {
      if (sellerId.trim().isEmpty) return const <SellerInventoryModel>[];
      final user = await ref.read(authUserProvider.future);
      if (user == null ||
          !user.active ||
          (!user.isAdmin && (!user.isSeller || user.id != sellerId.trim()))) {
        return const <SellerInventoryModel>[];
      }
      final tenantId = TenantScope.normalize(user.tenantId);
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(Collections.sellerInventory),
        tenantId: tenantId,
      );
      final docs = await fetchAllQueryDocuments(
        query
            .where('seller_id', isEqualTo: sellerId.trim())
            .where('active', isEqualTo: true),
      );
      return docs
          .map((d) => SellerInventoryModel.fromJson(d.data(), d.id))
          .toList();
    });

class SellerInventoryNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> _requireAdmin() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) throw StateError('Not authenticated');
    final me = await FirebaseFirestore.instance
        .collection(Collections.users)
        .doc(authUser.uid)
        .get();
    final role = (me.data()?['role'] as String? ?? '').trim();
    if (!isPrivilegedRoleName(role)) {
      throw StateError('Only admin can return stock to warehouse');
    }
  }

  /// Returns [qty] pairs of a seller inventory item back to the warehouse.
  /// Atomically:
  ///   1. Deducts from seller_inventory
  ///   2. Increments product_variants.quantity_available
  ///   3. Creates an audit record in inventory_transactions
  Future<void> returnToWarehouse({
    required String sellerInventoryDocId,
    required String variantId,
    required int qty,
    required String sellerId,
    required String sellerName,
    required String variantName,
    required String productId,
    required String createdBy,
    String? notes,
  }) async {
    await _requireAdmin();
    if (sellerInventoryDocId.trim().isEmpty) {
      throw ArgumentError('sellerInventoryDocId must not be empty');
    }
    if (variantId.trim().isEmpty) {
      throw ArgumentError('variantId must not be empty');
    }
    if (sellerId.trim().isEmpty) {
      throw ArgumentError('sellerId must not be empty');
    }
    if (productId.trim().isEmpty) {
      throw ArgumentError('productId must not be empty');
    }
    if (qty <= 0) throw ArgumentError('qty must be greater than 0');
    final normalizedCreatedBy = createdBy.trim();
    if (normalizedCreatedBy.isEmpty) {
      throw ArgumentError('createdBy must not be empty');
    }
    final currentUser = await ref.read(authUserProvider.future);
    final tenantId = TenantScope.normalize(currentUser?.tenantId);
    if (tenantId == null) {
      throw StateError('An active workspace is required to return stock');
    }
    if (FirebaseAuth.instance.currentUser?.uid != normalizedCreatedBy) {
      throw ArgumentError('createdBy must match the authenticated user');
    }

    final normalizedSellerId = sellerId.trim();
    final db = FirebaseFirestore.instance;
    final sellerInventoryRef = db
        .collection(Collections.sellerInventory)
        .doc(sellerInventoryDocId);
    final variantRef = db
        .collection(Collections.productVariants)
        .doc(variantId);
    final auditRef = db.collection(Collections.inventoryTransactions).doc();

    await db.runTransaction<void>((transaction) async {
      final sellerSnapshot = await transaction.get(sellerInventoryRef);
      final variantSnapshot = await transaction.get(variantRef);
      if (!sellerSnapshot.exists || !variantSnapshot.exists) {
        throw StateError('Stock record was not found');
      }
      final sellerData = sellerSnapshot.data()!;
      final variantData = variantSnapshot.data()!;
      final availableSellerQty =
          (sellerData['quantity_available'] as num?)?.toInt() ?? 0;
      if (TenantScope.normalize(sellerData['tenant_id'] as String?) !=
              tenantId ||
          TenantScope.normalize(variantData['tenant_id'] as String?) !=
              tenantId ||
          sellerData['seller_id'] != normalizedSellerId ||
          sellerData['variant_id'] != variantId ||
          sellerData['product_id'] != productId) {
        throw StateError('Stock records do not match the active workspace');
      }
      if (availableSellerQty < qty) {
        throw ArgumentError('Cannot return more stock than the seller has');
      }

      final warehouseQty =
          (variantData['quantity_available'] as num?)?.toInt() ?? 0;
      final now = Timestamp.now();
      transaction.update(sellerInventoryRef, {
        'quantity_available': availableSellerQty - qty,
        'updated_at': now,
      });
      transaction.update(variantRef, {
        'quantity_available': warehouseQty + qty,
        'updated_at': now,
      });
      transaction.set(auditRef, {
        'type': 'return_to_warehouse',
        'seller_id': normalizedSellerId,
        'seller_name': sellerName,
        'variant_id': variantId,
        'variant_name': variantName,
        'product_id': productId,
        'quantity': qty,
        'seller_previous_quantity': availableSellerQty,
        'seller_new_quantity': availableSellerQty - qty,
        'warehouse_previous_quantity': warehouseQty,
        'warehouse_new_quantity': warehouseQty + qty,
        'notes': notes,
        'created_by': normalizedCreatedBy,
        'created_at': now,
        'tenant_id': tenantId,
      });
    });
  }
}

final sellerInventoryNotifierProvider =
    AsyncNotifierProvider<SellerInventoryNotifier, void>(
      SellerInventoryNotifier.new,
    );
