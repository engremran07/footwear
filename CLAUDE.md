# ShoesERP — AI Coder Instructions (CLAUDE.md)

> Before writing any code, read AGENTS.md sections 2 (stack), 3 (collections), 5 (routes).
> These two files are the complete specification. Do not invent outside them.

---

## 0. Session Bootstrap Checklist

Every new conversation or sub-agent session must complete:

- Read AGENTS.md sections 2 (stack), 3 (collections), 5 (routes)
- Confirm what is already built (check AGENTS.md section 9 tracker)
- Never re-implement what is already done unless explicitly asked

---

## 1. Non-Negotiable Rules

### R1 — Never Write to `pnl_snapshots` from Flutter

The Dart app must NEVER call `.set()`, `.update()`, or `.add()` on the `pnl_snapshots` collection.
This collection is written ONLY by Cloud Functions via the Admin SDK.
If asked to add P&L write logic to the app, refuse and explain the architecture.

### R2 — Role Gate Every Write UI Element

Every form, button, FAB, or action that modifies data must gate on role:

```dart
if (user.role == UserRole.admin || user.role == UserRole.manager)
  ElevatedButton(onPressed: ..., child: const Text('Save'))
```

Or use the `RoleGuard` widget. Viewer, worker_pk, and worker_ksa roles may never see write UI.

### R3 — All Firestore Mutations Through Providers

Never call `FirebaseFirestore.instance` directly from a screen or widget file.
Always call a method on a provider notifier. Screens dispatch; providers execute.

### R4 — Streams Over One-Shot Reads

Use `StreamProvider<T>` for every list view and detail view.
`.get()` is only acceptable inside notifier methods for point-in-time lookups.

### R5 — Immutable After Approval

`worker_payments` with `status: 'approved'` or `status: 'paid'` MUST NOT have edit or delete buttons.
`order_returns` with `status: 'completed'` are read-only — no edits permitted.
Gate both in UI and rely on Firestore rules as a server-side backstop.

### R6 — Timestamps Are Always Firestore Timestamps

Always use `Timestamp.now()` from `cloud_firestore`. Never `DateTime.now().toIso8601String()`.
Store `Timestamp`, display with `DateFormat` from `intl`.

### R7 — One File Per Feature Unit

- One Dart model per file in `models/`
- One provider (or notifier pair) per file in `providers/`
- One screen per file in `screens/`

### R8 — No Extra Packages

Add ZERO packages beyond what is locked in AGENTS.md section 2.
If a feature seems to need a new package, ask whether a built-in Flutter or Firebase API covers it first.

Approved packages (locked):

- `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`
- `flutter_riverpod`, `riverpod_annotation`
- `go_router`, `fl_chart`, `intl`, `cached_network_image`
- `image_picker`, `uuid`, `logger`
- `excel: ^4.0.6` — used ONLY for xlsx export via `exportToExcel()` in `lib/core/utils/excel_export.dart`

### R9 — Returns Never Auto-Write P&L

`onReturnApproved.js` does NOT write to `pnl_snapshots` or `cash_transactions`.
Cash/refund entry is created manually by manager via `/cash` after physical refund is confirmed.

### R10 — Composite Indexes Required for Every `.where()` + `.orderBy()`

Every Firestore query that combines `.where(fieldA)` with `.orderBy(fieldB)` where `fieldA ≠ fieldB` REQUIRES a composite index in `firestore.indexes.json`. Missing indexes cause lists to silently return empty.

- Before adding any new StreamProvider with a compound query, add the index to `firestore.indexes.json`
- Deploy immediately: `firebase deploy --only firestore:indexes`
- See AGENTS.md Section 10 for the full required index table (20 indexes)
- Queries with just `.orderBy()` (no `.where()`) use automatic single-field indexes — no entry needed
- Queries with just `.where()` (no `.orderBy()`) also do not need composite indexes

### R11 — DropdownButtonFormField Uses `initialValue:` Not `value:`

In Flutter 3.22+, `DropdownButtonFormField` deprecated the `value:` parameter. Always use `initialValue:` instead:

```dart
// WRONG — deprecated, causes analyzer warning:
DropdownButtonFormField<String>(value: myValue, ...)

// CORRECT:
DropdownButtonFormField<String>(initialValue: myValue, ...)
```

---

## 2. Code Patterns (canonical — use these and no others)

### Model (Dart)

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductModel {
  final String id;
  final String sku;
  final String name;
  final double sellPrice;
  final Timestamp createdAt;

  const ProductModel({
    required this.id,
    required this.sku,
    required this.name,
    required this.sellPrice,
    required this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json, String docId) {
    return ProductModel(
      id: docId,
      sku: json['sku'] as String,
      name: json['name'] as String,
      sellPrice: (json['sell_price'] as num).toDouble(),
      createdAt: json['created_at'] as Timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'sku': sku,
    'name': name,
    'sell_price': sellPrice,
    'created_at': createdAt,
  };

  ProductModel copyWith({String? id, String? sku, String? name,
      double? sellPrice, Timestamp? createdAt}) {
    return ProductModel(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      sellPrice: sellPrice ?? this.sellPrice,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
```

### StreamProvider (Riverpod)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../core/constants/collections.dart';

final productsProvider = StreamProvider<List<ProductModel>>((ref) {
  return FirebaseFirestore.instance
      .collection(Collections.products)
      .where('active', isEqualTo: true)
      .orderBy('created_at', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => ProductModel.fromJson(doc.data(), doc.id))
          .toList());
});
```

### AsyncNotifier (Riverpod — for writes)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/collections.dart';

class ProductNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    await db.collection(Collections.products).add({
      ...data,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
  }

  Future<void> update(String id, Map<String, dynamic> data) async {
    final db = FirebaseFirestore.instance;
    await db.collection(Collections.products).doc(id).update({
      ...data,
      'updated_at': Timestamp.now(),
    });
  }
}

final productNotifierProvider =
    AsyncNotifierProvider<ProductNotifier, void>(ProductNotifier.new);
```

### Screen (ConsumerWidget)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProductsListScreen extends ConsumerWidget {
  const ProductsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final user = ref.watch(authUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: products.when(
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(title: Text(list[i].name)),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: (user?.isManager ?? false)
          ? FloatingActionButton(
              onPressed: () => context.push('/products/new'),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
```

---

## 3. Collections Class (canonical reference)

```dart
// lib/core/constants/collections.dart
class Collections {
  static const users              = 'users';
  static const products           = 'products';
  static const inventoryBatches   = 'inventory_batches';
  static const inventoryItems     = 'inventory_items';
  static const orders             = 'orders';
  static const orderItems         = 'order_items';
  static const customers          = 'customers';
  static const workers            = 'workers';
  static const workerPayments     = 'worker_payments';
  static const expenses           = 'expenses';
  static const cashTransactions   = 'cash_transactions';
  static const cashApprovals      = 'cash_approvals';
  static const expenseApprovals   = 'expense_approvals';
  static const pnlSnapshots       = 'pnl_snapshots';
  static const suppliers          = 'suppliers';
  static const purchaseOrders     = 'purchase_orders';
  static const qcRecords          = 'qc_records';
  static const wasteRecords       = 'waste_records';
  static const settings           = 'settings';
  static const orderReturns       = 'order_returns';
}
```

---

## 4. UserModel With Role Helpers

```dart
enum UserRole { admin, manager, viewer, workerPk, workerKsa }

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final bool active;

  bool get isAdmin    => role == UserRole.admin;
  bool get isManager  => role == UserRole.manager || role == UserRole.admin;
  bool get isViewer   => true;  // all roles can view
  bool get canWrite   => role == UserRole.admin || role == UserRole.manager;
  bool get isWorker   => role == UserRole.workerPk || role == UserRole.workerKsa;
}
```

---

## 5. RoleGuard Widget

```dart
// widgets/role_guard.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';

class RoleGuard extends ConsumerWidget {
  final Widget child;
  final bool Function(UserModel) allowed;
  final Widget? fallback;

  const RoleGuard({
    super.key,
    required this.child,
    required this.allowed,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user == null || !allowed(user)) return fallback ?? const SizedBox.shrink();
    return child;
  }
}

// Usage:
// RoleGuard(
//   allowed: (u) => u.isManager,
//   child: ElevatedButton(onPressed: ..., child: Text('Create')),
// )
```

---

## 6. Module Specifications

### Dashboard

- 6 stat cards: Total Revenue (MTD), Net Profit (MTD), Active Orders, Stock Pairs, Pending Approvals, Workers Active
- Revenue + Net Profit from: `pnl_snapshots[YYYY-MM]` (stream single doc)
- Active Orders: `orders.where(status, in: [pending, processing]).count`
- Stock Pairs: `settings.doc('global').low_stock_threshold` vs `products.sum(stock_count)`
- No edits, no forms

### P&L Screen

- Year selector → reads 12 `pnl_snapshots` docs by ID
- Bar chart via `fl_chart` — revenue vs expenses per month
- Summary row: Revenue / COGS / Gross Profit / Expenses / Worker Cost / Net Profit
- Export (admin): plain text or share sheet — no PDF generation

### Products

- List with search by name/sku, filter by active
- Detail: shows stock_count, sizes, cost/sell price
- Form: sku, name, category, sizes (multi-input), cost_price, sell_price, image upload (Firebase Storage)

### Inventory

- List: batches by status — filter by status
- Detail: batch stats + list of inventory_items for that batch
- Form: product, qty_produced, cost_total, assign worker
- Status update buttons (in_production → qc_pending → Cloud Function takes over)

### Orders

- List with status filter
- Form: pick customer (dropdown stream), add line items (product + size + qty)
- Total auto-calculated: sum(unit_price × qty) for each line
- Detail: order lines, status timeline, dispatch button (manager+)

### Workers

- Tabs: PK Workers | KSA Workers (filter by type)
- Detail: worker stats, payment history list
- Pay button → WorkerPaymentFormScreen
- Approved payments are read-only (no edit/delete)

### Expenses

- List: filter by category + status
- Form: category enum, amount, description, optional receipt image
- Approval creates an `expense_approvals` doc (Cloud Function updates expense + pnl)

### Cash

- Running total from `cash_transactions` stream
- Add cash_in / cash_out → creates `cash_transactions` + `cash_approvals` doc
- Pending list for admin to approve

### Approvals (admin only)

- Unified queue: pending `cash_approvals` + pending `expense_approvals`
- Approve/Reject buttons update the approval doc status
- Cloud Functions handle the cascade (status update on linked doc + pnl_snapshot update)

### Purchase Orders

- Form: supplier, expected delivery, line items (product, size, qty, unit_cost)
- Status update to `received` triggers Cloud Function → creates inventory_items
- Detail shows linked inventory_batch_id after receipt

### Suppliers

- CRUD — name, contact_name, phone, email, address, payment_terms
- Order history count (denormalized on supplier doc via Cloud Function)

### QC

- Shows batches in `qc_pending` status
- Inspector enters passed_qty + rejected_items (each with size + reason)
- Creates `qc_records` doc → Cloud Function fires onQCReject

### Waste

- Read-only list of `waste_records`
- Filter by worker_id, date range
- Disposed toggle (admin only updates `disposed` field)

### Reports

- Revenue by product: group `order_items` where status=dispatched by product_id
- Worker efficiency: worker_payments.pairs_count / worker_payments.amount
- Waste rate: waste_records.count / inventory_batches.qty_produced
- All from existing Firestore queries — no new aggregation collections

### Returns

- List: all `order_returns`, filter by status tabs (pending / approved / rejected / completed)
- Form (manager only, 3 steps):
  - Step 1: pick delivered order (dropdown stream)
  - Step 2: per-line item selection with qty_returned (+1 / +12 / +20 quick-add), condition (good/damaged), reason
  - Step 3: return type (full/partial/replacement/damage_claim), refund_amount, notes
- Detail: full breakdown, approve/reject buttons (admin only), "Mark Complete" button after refund confirmed
- Completed returns are read-only
- No automatic P&L entry — cash refund logged manually via `/cash`

### Settings

- Company name, logo upload, currency config
- Tax rate, low_stock_threshold
- Admin-only user list (name, role, active toggle)

---

## 7. Error Handling

| Layer | Approach |
| --- | --- |
| Providers | `AsyncValue`; wrap in `try/catch`, rethrow so Riverpod surfaces as error state |
| Screens | `.when(data:, loading:, error:)` — always provide error widget with message |
| Forms | `Form` + `GlobalKey<FormState>` + `validators.dart` — validate before calling provider |
| Cloud Functions | `try/catch` + `functions.logger.error()` + rethrow for retry |

---

## 8. Security Checklist (Before Every PR)

- `pnl_snapshots` — zero write calls from Dart in entire codebase
- Every FAB / Save / Delete button wrapped in role check
- No `FirebaseFirestore.instance` calls in `screens/` or `widgets/`
- No `print()` — use `debugPrint()` or logger package
- All text inputs passed through `validators.dart` before write
- No secrets or API keys in Dart source — use Firebase Remote Config or env
- All `worker_payments` edit/delete paths blocked for approved status
- All `order_returns` edit paths blocked for completed status

---

## 9. What AI Must Never Do

| Prohibited | Why |
| --- | --- |
| Write to `pnl_snapshots` from Flutter | Cloud Functions own this — app writes break aggregation |
| Use `setState` for Riverpod-managed state | Use `ref.invalidate()` or `AsyncNotifier` |
| Call Firestore directly from screen/widget | Violates provider pattern; untestable |
| Add packages not in pubspec.yaml | Stack is locked |
| Create new Firestore collections | 20 is final |
| Add screens not in AGENTS.md section 5 | Route list is locked |
| Allow editing approved `worker_payments` | Business rule; payment integrity |
| Allow editing completed `order_returns` | Business rule; return integrity |
| Aggregate P&L with queries | Read snapshots only; functions maintain them |
| Skip approval workflow for expenses/cash | Bypasses P&L integrity |
| Use `DateTime.now()` for Firestore timestamps | Must use `Timestamp.now()` |
| Auto-create cash entries on return approval | Cash refund is manually confirmed by manager |
| Add `.where(A).orderBy(B)` without composite index | Lists silently return empty without the index in `firestore.indexes.json` |
| Use `value:` in `DropdownButtonFormField` | Deprecated since Flutter 3.22 — use `initialValue:` |
| Create a separate `/users` route | User management lives in Settings screen only |
