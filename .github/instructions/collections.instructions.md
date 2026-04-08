---
applyTo: "app/lib/**/*.dart"
---

# Firestore Collection Constants

## Rule: Never Use Raw Collection Strings

All Firestore collection references MUST use constants from `app/lib/core/constants/collections.dart`. Never pass raw string literals to `.collection()`.

```dart
// ✅ CORRECT
db.collection(Collections.transactions).doc(txId)
db.collection(Collections.inventoryTransactions)

// ❌ WRONG — will be caught by CI hygiene gate
db.collection('transactions').doc(txId)
db.collection('inventory_transactions')
```

## Enforcement

CI gate (`hygiene` job, Gate 1) runs:
```bash
grep -rn "\.collection('" app/lib/ | grep -v Collections\.
```
Zero matches required. Build fails on any raw literal.

## Canonical Collection Map

| Constant | Firestore Name | Purpose |
|----------|---------------|---------|
| `Collections.users` | `users` | User profiles + roles |
| `Collections.products` | `products` | Product catalog |
| `Collections.productVariants` | `product_variants` | SKU/size/color variants |
| `Collections.sellerInventory` | `seller_inventory` | Per-seller stock allocations |
| `Collections.inventoryTransactions` | `inventory_transactions` | All stock movement audit log |
| `Collections.routes` | `routes` | Delivery routes |
| `Collections.shops` / `Collections.customers` | `customers` | Retail shops (legacy name) |
| `Collections.transactions` | `transactions` | Financial ledger entries |
| `Collections.invoices` | `invoices` | Sale/return invoices |
| `Collections.settings` | `settings` | App configuration |

> **Note:** The Firestore collection for shops is `customers` — a legacy naming. Always use `Collections.shops` in code; the constant resolves to `'customers'` internally. Do NOT create a separate `customers` collection.

## Breakage Chain: Collection Name Change

If a collection constant value changes:
1. Update `collections.dart`
2. Verify all queries with `.collection(constant)` still resolve
3. Update `firestore.rules` match paths
4. Update `firestore.indexes.json` collection names
5. Update ALL 5 docs: `AGENTS.md`, `CLAUDE.md`, `README.md`, `app/README.md`, `SYSTEM_DEEP_DIVE_2026-03-27.md`
6. Re-deploy rules + indexes

## Adding a New Collection

1. Add constant to `collections.dart`
2. Add rules block to `firestore.rules` (deny-by-default)
3. Add to canonical list in `AGENTS.md §1`
4. Add composite indexes as required
5. Add to this instructions file
