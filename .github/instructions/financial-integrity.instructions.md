---
applyTo: "app/lib/providers/invoice_provider.dart,app/lib/providers/transaction_provider.dart,app/lib/screens/create_sale_invoice_screen.dart,app/lib/screens/shop_detail_screen.dart"
---

# Financial Integrity Rules

## The Three Financial Pathways — NEVER MIX

### Pathway 1: SALE WITH STOCK
```
CreateSaleInvoiceScreen → InvoiceNotifier.createSaleInvoice()
→ Invoice + cash_out tx + optional cash_in tx + seller_inventory deduction
   (all in one atomic batch)
USE WHEN: new goods delivered to shop, stock deduction required
```

### Pathway 2: CASH COLLECTION (old debt, no new goods)
```
ShopDetailScreen → TransactionNotifier.create(type: 'cash_in')
→ Cash_in ledger entry ONLY. No invoice. No stock movement.
USE WHEN: collecting outstanding balance, no new delivery
```

### Pathway 3: VOID / RETURN
```
InvoiceNotifier.voidInvoice() — admin only
→ Returns stock to inventory (seller_inventory or warehouse)
→ Two refund modes: cashRefund (paid back) or creditBalance (deduct from balance)
→ Issues ONE reversal transaction (return tx). Cash refund adds a second cash_out tx.
```

### Anti-Patterns (FORBIDDEN)
- ❌ Creating an invoice for cash-only collection
- ❌ Creating a standalone transaction for a new stock sale
- ❌ Mixing invoice creation with direct balance mutation
- ❌ Calling `createSaleInvoice` without stock deduction when inventory exists

## Atomic Batch Requirement

Every financial operation that touches ≥2 collections MUST use Firestore batched writes. NO sequential `.set()` or `.update()` calls.

```dart
// ✅ CORRECT: atomic batch
final batch = db.batch();
batch.set(invoiceRef, invoiceData);
batch.update(customerRef, {'balance': FieldValue.increment(amount)});
batch.update(inventoryRef, {'quantity_available': FieldValue.increment(-qty)});
await batch.commit(); // atomic — all or nothing

// ❌ WRONG: can leave partial state on failure
await db.collection(Collections.invoices).doc(id).set(invoiceData);
await db.collection(Collections.customers).doc(cid).update({...});
```

## Validation Requirements

### Invoice Creation Guards
```dart
// amountReceived must not exceed total
if (amountReceived > total) throw ArgumentError(...)

// total must equal subtotal minus discount (within 0.01 float tolerance)
if ((total - (subtotal - discount)).abs() > 0.01) throw ArgumentError(...)

// Item subtotals must sum to subtotal
final computed = items.fold(0.0, (a, it) => a + it.qty * it.unitPrice);
if ((computed - subtotal).abs() > 0.01) throw ArgumentError(...)

// Max invoice cap
if (total > 999999.99) throw ArgumentError(...)

// At least 1 item required
if (items.isEmpty) throw ArgumentError(...)

// createdBy must be non-empty
if (createdBy.trim().isEmpty) throw ArgumentError(...)
```

## Transaction Update Rules

Sellers can ONLY update `description` on transactions they created. Amounts, types, and dates are IMMUTABLE for sellers.

```dart
// ✅ CORRECT for sellers — only annotation
await notifier.updateTransactionNote(txId: id, description: desc);

// ✅ CORRECT for admins — full update
await notifier.updateTransaction(txId: id, newAmount: amt, newType: type, ...);
```

Firestore rules enforce: seller update `hasOnly(['description', 'updated_at'])`.

## Breakage Chain: Financial Field Change

If you add a new field to invoices/transactions:
1. Add to model (`fromJson` default value + `toJson` + `copyWith`)
2. Add to provider batch payload
3. Validate in Firestore rules create/update
4. Add to Firestore index if queried
5. Add test: default value round-trip + edge-case validation

## Void Invoice (Admin Only)

`voidInvoice()` must be called only by admins. UI must not show void button to sellers. The method:
1. Checks `!user.isAdmin` → throws if not admin
2. Updates invoice status to `void`
3. Returns stock to source inventory atomically
4. Issues reversal transaction
5. Handles `creditBalance` vs `cashRefund` mode
