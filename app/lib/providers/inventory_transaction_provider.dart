import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/collections.dart';
import '../core/utils/tenant_scope.dart';
import '../models/inventory_transaction_model.dart';
import 'auth_provider.dart';

/// All inventory transactions (admin â€” transfer history).
final allInventoryTransactionsProvider =
    StreamProvider.autoDispose<List<InventoryTransactionModel>>((ref) {
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
        FirebaseFirestore.instance.collection(
          Collections.inventoryTransactions,
        ),
        tenantId: tenantId,
      );
      return query
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => InventoryTransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });

/// Inventory transactions for a single seller.
final sellerInventoryTransactionsProvider = StreamProvider.autoDispose
    .family<List<InventoryTransactionModel>, String>((ref, sellerId) {
      final normalizedSellerId = sellerId.trim();
      if (normalizedSellerId.isEmpty) return const Stream.empty();
      final tenantId = ref.watch(
        authUserProvider.select(
          (s) => TenantScope.normalize(s.value?.tenantId),
        ),
      );
      final query = TenantScope.applyToQuery(
        FirebaseFirestore.instance.collection(
          Collections.inventoryTransactions,
        ),
        tenantId: tenantId,
      );
      return query
          .where('seller_id', isEqualTo: normalizedSellerId)
          .orderBy('created_at', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) => InventoryTransactionModel.fromJson(d.data(), d.id))
                .toList(),
          );
    });
