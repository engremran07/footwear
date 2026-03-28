---
name: transactions-ledger
description: "Use when: creating, editing, or deleting transactions; balance corrections; ledger display; atomic batch writes; running balance reports."
---

# ShoesERP Transactions & Ledger Skill

## Transaction Model

**Collection:** `transactions`
**Key fields:**
- `shop_id` / `shop_name` — may be empty for pure customer transactions
- `route_id` — required for seller write permission check
- `customer_id` / `customer_name`
- `type` — `'cash_in'` | `'cash_out'`
- `sale_type` — `'cash'` | `'credit'`
- `amount` — positive double
- `items` — `List<TransactionItem>` (variantId, sku, productName, size, color, qty, unitPrice, subtotal)
- `created_by` — seller/admin UID
- `created_at` — Timestamp

## Balance Logic

```
cash_out → balance += amount   (customer owes more)
cash_in  → balance -= amount   (debt reduces)
```

**Customer balance is stored in `customers/{id}.balance`** — always updated atomically via batch write alongside the transaction doc.

## Atomic Batch Write Pattern

```dart
final batch = db.batch();
batch.set(txRef, txData);                      // 1. Write TX doc
batch.update(customerRef, {'balance': FieldValue.increment(delta)});  // 2. Update balance
// optionally: batch.update(variantRef, {'quantity_available': FieldValue.increment(-qty)});
await batch.commit();                          // Atomic
```

## Delete Transaction

Reversal delta:
```dart
final reversalDelta = type == 'cash_out' ? -amount : amount;
```
Apply to `customers/{customerId}.balance`.

## Update Transaction

Net balance change = `(-oldDelta) + newDelta` where:
- `oldDelta = oldType == 'cash_out' ? oldAmount : -oldAmount`
- `newDelta = newType == 'cash_out' ? newAmount : -newAmount`

## Firestore Rules

```
allow create: if isAdmin() || (isSellerForRoute(routeId) && created_by == uid)
allow update: if isAdmin() || (isSeller() && created_by == uid)
allow delete: if isAdmin() || (isSeller() && created_by == uid)
```

## UI Pattern — Edit/Delete

Use `PopupMenuButton` as `ListTile.trailing` for eligible users:
```dart
trailing: canEdit
    ? PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (v) { if (v == 'edit') ...; if (v == 'delete') ...; },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: ...),
          PopupMenuItem(value: 'delete', child: ...),
        ],
      )
    : null,
```

## Running Balance (for CA-grade statements)

Sort transactions ASC by `created_at`, then iterate:
```dart
double running = 0;
for (final tx in sorted) {
  running += tx.type == 'cash_out' ? tx.amount : -tx.amount;
  rows.add([date, description, debit, credit, running]);
}
```

## Provider Validation Guards

Always validate before batch commit:
```dart
if (createdBy.trim().isEmpty) throw ArgumentError('createdBy must not be empty');
if (shopId.trim().isEmpty) throw ArgumentError('shopId must not be empty');
if (routeId.trim().isEmpty) throw ArgumentError('routeId must not be empty');
```
