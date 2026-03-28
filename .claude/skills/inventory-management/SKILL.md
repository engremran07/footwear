---
name: inventory-management
description: "Use when: adjusting warehouse stock, allocating seller inventory, deducting stock on sale, or fixing quantity_available field issues."
---

# Skill: Inventory Management

## Domain
Warehouse stock (product_variants) + seller-allocated stock (seller_inventory) in ShoesERP.

## Key Files
- `app/lib/providers/product_provider.dart` — allVariantsProvider, ProductNotifier.adjustStock()
- `app/lib/providers/seller_inventory_provider.dart` — sellerInventoryProvider, SellerInventoryNotifier
- `app/lib/screens/inventory_screen.dart` — admin stock adjustment UI
- `app/lib/models/product_model.dart` — ProductVariant with quantityAvailable

## Schema (CANONICAL)
```
product_variants/{variantId}
  - variant_name: String
  - quantity_available: int   ← ALWAYS use this field name (NOT stock_qty)
  - product_id: String
  - active: bool

seller_inventory/{docId}
  - seller_id: String
  - seller_name: String
  - product_id: String
  - variant_id: String
  - variant_name: String
  - quantity_available: int
  - active: bool
```

## Stock Units
- **pairsPerCarton** from settings (typically 12)
- Display using `AppFormatters.stock(qty, ppc)` → "2 ctn 1 dz 6 pr"
- Always store in PAIRS in Firestore

## Adjust Stock (Admin)
```dart
await ref.read(productNotifierProvider.notifier).adjustStock(
  variantId: variantId,
  cartons: c,
  dozens: d,
  pairs: p,
  ppc: ppc,
);
```

## Deduct Stock (Seller Sale)
```dart
await ref.read(sellerInventoryNotifierProvider.notifier).deductStock(
  docId: sellerInventoryDocId,
  qty: pairsSold,
);
```

## Seller Sale creates TransactionModel items via createSellerSale()
- Deducts from seller_inventory (NOT product_variants)
- Calls TransactionNotifier.createSellerSale() with sellerInventoryDeductions map

## Common Pitfalls
- Use `quantity_available` not `stock_qty` — schema was migrated
- Admin adjustStock touches product_variants; seller deductStock touches seller_inventory
- Transaction item deduction must match seller_inventory doc IDs (keys in deductions map)
