---
name: data-integrity
description: "Use when: handling atomic Firestore writes, preventing race conditions in invoice numbering, ensuring customer balance consistency, batch write patterns, historical data uploads."
---

# Skill: Data Integrity & Atomic Operations

## Core Principle
Every operation that touches multiple Firestore documents MUST use either:
1. **WriteBatch**: for operations where all-or-nothing is required (no sequential dependency)
2. **runTransaction**: for operations where read-compute-write must be atomic (e.g., counters)

## Invoice Number Generation (CRITICAL — Race Condition Fix Required)
```dart
// CURRENT CODE (BROKEN — race condition):
// invoice_provider.dart _nextInvoiceNumber()
final doc = await settingsRef.get();           // read
final next = (doc.data()?['last_invoice_number'] as int?) ?? 0) + 1;
await settingsRef.update({'last_invoice_number': next});  // write (not atomic!)
// Two concurrent calls can get the same number!

// FIXED — use runTransaction:
Future<String> _nextInvoiceNumber() async {
  final db = FirebaseFirestore.instance;
  final settingsRef = db.collection(Collections.settings).doc('global');
  
  final nextNum = await db.runTransaction<int>((txn) async {
    final doc = await txn.get(settingsRef);
    final current = (doc.data()?['last_invoice_number'] as int?) ?? 0;
    final next = current + 1;
    txn.update(settingsRef, {'last_invoice_number': next});
    return next;
  });
  
  return 'INV-${DateTime.now().year}-${nextNum.toString().padLeft(4, '0')}';
}
```

## Customer Balance Atomicity (Already Correct Pattern)
```dart
// invoice_provider.dart createInvoice():
final batch = db.batch();
batch.set(invoiceRef, invoiceData);
batch.update(customerRef, {
  'balance': FieldValue.increment(balanceDelta),
  'updated_at': Timestamp.now(),
});
await batch.commit(); // atomic ✅
```

## Transaction + Inventory Deduction (Atomic)
```dart
// When seller creates a sale with stock deduction:
final batch = db.batch();

// 1. Write transaction doc
batch.set(txRef, txData);

// 2. Update customer balance
batch.update(customerRef, {
  'balance': FieldValue.increment(balanceDelta),
  'updated_at': Timestamp.now(),
});

// 3. Deduct from seller_inventory (for each deduction item)
for (final entry in sellerInventoryDeductions.entries) {
  batch.update(sellerInventoryRef.doc(entry.key), {
    'quantity_available': FieldValue.increment(-entry.value),
    'updated_at': Timestamp.now(),
  });
}

await batch.commit(); // all 3 operations atomic ✅
```

## Historical Data Upload Pattern
For bulk data uploads (initial setup / data migration):
```dart
// Chunk writes in batches of 500 (Firestore batch limit = 500 operations)
Future<void> uploadHistoricalData<T>(
  List<T> items,
  CollectionReference col,
  Map<String, dynamic> Function(T) toJson,
) async {
  const chunkSize = 400; // leave headroom
  for (var i = 0; i < items.length; i += chunkSize) {
    final chunk = items.sublist(i, (i + chunkSize).clamp(0, items.length));
    final batch = FirebaseFirestore.instance.batch();
    for (final item in chunk) {
      batch.set(col.doc(), toJson(item));
    }
    await batch.commit();
    // Small delay to avoid write quota
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
```

## Company Prefix / Reference Number Patterns
Invoice prefix pattern: `INV-YYYY-NNNN`
- Year resets counter? Decision: NO — use global sequential counter for simplicity and audit uniqueness
- Alternative: per-year counter stored as `settings/2026.last_invoice_number`
- If multi-company: prefix with company code: `FW-INV-2026-0001`

```dart
// Multi-company prefix support (future-ready):
String _buildInvoiceNumber(String prefix, int year, int seq) {
  return '$prefix-$year-${seq.toString().padLeft(4, '0')}';
}
// e.g., 'INV', 2026, 42 → 'INV-2026-0042'
```

## Orphaned Data Detection
Scenarios where data can become inconsistent:
1. **Invoice created, customer balance update fails** → invoice exists but balance wrong
   - Prevention: WriteBatch (atomic) ✅
2. **User deleted from Auth but Firestore doc remains** → `active = false` soft-delete handles this ✅
3. **Seller inventory allocated but product variant deleted** → seller_inventory has orphaned `variant_id`
   - Detection: query seller_inventory where variant_id not in product_variants
4. **Transaction references deleted shop** → `shop_id` points to non-existent doc
   - Prevention: soft-delete only (never hard-delete shops that have transactions)

## Balance Reconciliation Check
Periodic integrity check (run as admin function or script):
```dart
// Check: sum of all transactions for a customer = customer.balance
Future<bool> reconcileCustomerBalance(String customerId) async {
  final txSnap = await FirebaseFirestore.instance
    .collection(Collections.transactions)
    .where('customer_id', isEqualTo: customerId)
    .get();
  
  double computed = 0;
  for (final doc in txSnap.docs) {
    final tx = TransactionModel.fromJson(doc.data(), doc.id);
    computed += tx.type == 'cash_out' ? tx.amount : -tx.amount;
  }
  
  final customerDoc = await FirebaseFirestore.instance
    .collection(Collections.customers)
    .doc(customerId)
    .get();
  final stored = (customerDoc.data()?['balance'] as num?)?.toDouble() ?? 0;
  
  return (computed - stored).abs() < 0.01; // within 1 cent tolerance
}
```

## Firestore Document Size Enforcement
Max recommended document size: 50 KB (enforced by `docSizeOk()` rule)
- Invoice with 50 items × 100 bytes each = 5 KB → safe ✅
- Settings doc with base64 logo (256×256 compressed) ≤ 50 KB → enforced ✅
- If document exceeds limit: split into sub-collections
  - e.g., `invoices/{id}/items/{itemId}` for invoices with 100+ items

## Idempotency (Safe Retry Pattern)
For operations that might be retried (network failures):
```dart
// Use deterministic document IDs for idempotent operations
final invoiceId = const Uuid().v5(Uuid.NAMESPACE_URL, 
  '${sellerId}_${shopId}_${Timestamp.now().millisecondsSinceEpoch}');
// If network fails and client retries, same document ID = update (not duplicate)
```
