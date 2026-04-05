---
name: erp-chartered-accountant
description: "Use when: reviewing financial flows, invoice lifecycle, balance accuracy, double-entry integrity, bad debt write-offs, credit control, audit trails, ERP accounting standards compliance."
---

# Skill: ERP Chartered Accountant & Financial Controls

## Domain
Financial controls, accounting accuracy, and ERP integrity for ShoesERP — a route/seller distribution business.

## Core Financial Rules (CA-Grade)

### 1. Double-Entry Ledger Integrity
Every financial transaction MUST affect exactly two sides:
```
Sale (credit invoice):
  DR: Accounts Receivable (customer.balance += total)
  CR: Sales Revenue (tracked in transactions collection)

Cash Collection:
  DR: Cash/Bank
  CR: Accounts Receivable (customer.balance -= amount)

Credit Note / Return:
  DR: Sales Revenue (reversal)
  CR: Accounts Receivable (customer.balance -= credited)
```

### 2. Invoice Numbering (Sequential, No Gaps)
- Format: `INV-YYYY-NNNN` (e.g., INV-2026-0001)
- Counter stored atomically in `settings/global.last_invoice_number`
- **MUST use Firestore Transaction** for atomic increment — prevents duplicate numbers
- Void/cancelled invoices keep their number with `status: 'void'` (no number reuse)

### 3. Customer Balance Rules
```
balance > 0 → customer owes money (debit/AR position)
balance = 0 → no outstanding amount
balance < 0 → overpayment (credit on account)
```
Balance MUST be updated atomically with the transaction/invoice in a single batch:
```dart
final batch = db.batch();
batch.set(txRef, txData);
batch.update(customerRef, {'balance': FieldValue.increment(delta), 'updated_at': Timestamp.now()});
await batch.commit();
```

### 4. Invoice Lifecycle State Machine
```
draft → issued → (partial → paid) or (issued → void)
            ↓
       credit_note (linked_invoice_id = original)
```
**Illegal transitions:**
- `paid → draft` (must reverse via credit note)
- `void → any` (terminal state)
- Issued invoice amount cannot be changed (must void and reissue)

### 5. Fake Invoice Prevention (Anti-Fraud Controls)
Implemented controls:
- `route_id` required on seller invoices → links sale to authorized route
- `seller_id` captured on invoice → non-repudiation
- `created_by` = authenticated UID → cannot be spoofed
- `docSizeOk()` prevents data stuffing
- `withinWriteRate()` prevents rapid duplicate submissions
- Items list with specific `variant_id`, `qty`, `unit_price` → line-item audit trail

Additional controls to verify:
- Invoice total = sum of item subtotals − discount (server-side validation needed)
- `amount_received` ≤ `total + previous_balance` (no negative balance creation)
- Seller can only create invoices for shops on their assigned route

### 6. Bad Debt Write-Off Pattern
```dart
// When a customer balance is written off:
// 1. Create a 'credit_note' transaction with negative amount
// 2. Update customer.balance to 0
// 3. Log in inventory_transactions for audit trail
// Flag: set customer field 'bad_debt_written_off': true
```

### 7. Period-End Financial Reporting Requirements
Monthly period: `YYYY-MM` format (e.g., `2026-04`)
Reports needed:
- Cash flow statement (cash_in vs cash_out per period)
- Outstanding receivables by customer
- Sales by route/seller
- Stock valuation (pairs × unit_cost)

### 8. Audit Trail Fields (Every Document)
Every business document MUST have:
- `created_by`: UID string
- `created_at`: Timestamp
- `updated_at`: Timestamp
- For invoices: `seller_id`, `seller_name`, `route_id`

### 9. ERP Data Integrity Checks
Pre-save validations (in provider, not just UI):
```dart
assert(invoice.total >= 0, 'Invoice total cannot be negative');
assert(invoice.items.isNotEmpty || invoice.total == 0, 'Empty items require zero total');
assert(invoice.amountReceived <= invoice.total, 'Cannot receive more than invoice total on creation');
assert(invoice.subtotal - invoice.discount == invoice.total, 'Total must equal subtotal minus discount');
```

### 10. CA-Grade Statement Display
Running balance column for customer statements:
```
Date      | Description          | Debit   | Credit  | Balance
----------|----------------------|---------|---------|--------
01/04/26  | INV-2026-0001 (sale) | 5,000   |         | 5,000
03/04/26  | Cash received        |         | 3,000   | 2,000
05/04/26  | INV-2026-0002 (sale) | 2,500   |         | 4,500
```
Implemented in: `app/lib/screens/customer_detail_screen.dart`

## Financial Validation Functions (Dart)
```dart
// Validate invoice totals are internally consistent
bool invoiceTotalsValid(InvoiceModel inv) {
  final computed = inv.items.fold<double>(0, (s, i) => s + i.subtotal);
  final diff = (computed - inv.subtotal).abs();
  return diff < 0.01; // allow 1 cent floating point tolerance
}

// Validate balance delta is correct
double expectedBalanceDelta(InvoiceModel inv) {
  return inv.saleType == 'credit'
    ? inv.total - inv.amountReceived  // credit sale: net unpaid goes to AR
    : 0.0;                            // cash sale: fully paid, no AR change
}
```

## Compliance Checklist
- [ ] All invoices have sequential non-duplicate numbers
- [ ] Customer balance updated atomically with every invoice/transaction
- [ ] Credit notes linked to original invoice via `linked_invoice_id`
- [ ] Void invoices preserve number, set status='void'
- [ ] No direct balance modification without matching transaction
- [ ] Running balance column in customer statement screen
- [ ] Seller invoices require valid `route_id` matching assignment
- [ ] Items subtotals sum to invoice subtotal (within 0.01 tolerance)
- [ ] Amount received ≤ invoice total on creation
