# ShoesERP — Master Architecture Reference (AGENTS.md)

> Read this file at the start of every AI session before writing any code.
> This is the single source of truth for stack, collections, routes, and conventions.
> Sections 2, 3, 4, 5 are authoritative — do not invent outside them.

---

## 1. Business Context

ShoesERP manages a footwear manufacturing and distribution business with:

- Production workers in Pakistan (PK) assembling shoes in batches
- Warehouse/dispatch workers in Saudi Arabia (KSA) handling outbound orders
- Financial tracking: expenses, cash, worker payroll, P&L all in one system
- Admin/manager office staff creating orders and approving transactions

---

## 2. Stack

| Layer | Technology |
| --- | --- |
| App | Flutter 3.x (Dart) — Android + iOS + Web |
| State | flutter_riverpod ^2.6.1 + riverpod_annotation |
| Routing | go_router ^14.x |
| DB | Cloud Firestore (real-time streams only) |
| Auth | Firebase Authentication |
| Functions | Firebase Cloud Functions — Node.js 20 |
| Storage | Firebase Storage (expense receipts + product images only) |
| Charts | fl_chart ^0.69.x |

No Express, no REST API, no separate server, no SQL DB, no paid third-party tools.

**pubspec.yaml (locked):**

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
  firebase_storage: ^12.3.2
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1
  go_router: ^14.6.1
  fl_chart: ^0.69.0
  intl: ^0.19.0
  cached_network_image: ^3.4.1
  image_picker: ^1.1.2
  uuid: ^4.5.1
  logger: ^2.4.0
  excel: ^4.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  riverpod_generator: ^2.6.1
  build_runner: ^2.4.13
  custom_lint: ^0.7.0
  riverpod_lint: ^2.6.1
```

---

## 3. Firestore Collections

Every document field is defined below. Never invent extra fields or collections.

### 3.1 `users`

```text
id              String   (= Firebase Auth UID)
email           String
display_name    String
role            String   enum: admin | manager | viewer | worker_pk | worker_ksa
worker_id       String?  (only for worker_pk / worker_ksa roles)
active          bool
created_at      Timestamp
updated_at      Timestamp
```

### 3.2 `products`

```text
id              String
sku             String    (unique)
name            String
category        String
sizes           List<String>
cost_price      double
sell_price      double
image_url       String?
stock_count     int       (maintained by Cloud Functions)
active          bool
created_at      Timestamp
updated_at      Timestamp
```

### 3.3 `inventory_batches`

```text
id                String
product_id        String
purchase_order_id String?
supplier_id       String?
qty_produced      int
qty_passed        int       (set by Cloud Function after QC)
qty_rejected      int
cost_total        double    (materials + overhead)
cost_per_pair     double    (set by Cloud Function on complete)
status            String    enum: draft | in_production | qc_pending | qc_issues | qc_passed | complete
source            String    enum: production | purchase_order
last_qc_id        String?
completed_at      Timestamp?
created_at        Timestamp
updated_at        Timestamp
```

### 3.4 `inventory_items`

```text
id                  String
product_id          String
product_name        String
sku                 String?
size                String
inventory_batch_id  String
purchase_order_id   String?
cost_per_pair       double
status              String  enum: available | reserved | sold | rejected | disposed
order_id            String?
order_item_id       String?
qc_record_id        String?
reserved_at         Timestamp?
created_at          Timestamp
updated_at          Timestamp
```

### 3.5 `orders`

```text
id              String
customer_id     String
customer_name   String  (denormalized)
status          String  enum: pending | processing | shipped | delivered | cancelled
total           double
notes           String?
created_by      String  (uid)
created_at      Timestamp
updated_at      Timestamp
```

### 3.6 `order_items`

```text
id                  String
order_id            String
product_id          String
product_name        String
size                String
qty                 int
unit_price          double
subtotal            double
inventory_batch_id  String?
status              String  enum: pending | reserved | stock_issue | dispatched | returned
created_at          Timestamp
updated_at          Timestamp
```

### 3.7 `customers`

```text
id              String
name            String
phone           String
email           String?
address         String?
city            String?
country         String
balance         double  (outstanding receivable)
total_orders    int
created_at      Timestamp
updated_at      Timestamp
```

### 3.8 `workers`

```text
id              String
name            String
type            String    enum: pk | ksa
rate_per_pair   double
currency        String    enum: PKR | SAR
total_earned    double    (incremented by Cloud Function)
pairs_produced  int
active          bool
joined_at       Timestamp
created_at      Timestamp
updated_at      Timestamp
```

### 3.9 `worker_payments`

```text
id              String
worker_id       String
worker_name     String
worker_type     String    enum: pk | ksa
amount          double
pairs_count     int
period          String    YYYY-MM
status          String    enum: draft | pending | approved | paid
approved_by     String?
approved_at     Timestamp?
notes           String?
created_at      Timestamp
updated_at      Timestamp
```

### 3.10 `expenses`

```text
id              String
category        String  enum: rent | utilities | transport | marketing | other
amount          double
description     String
receipt_url     String?
status          String  enum: draft | pending_approval | approved | rejected
created_by      String
approved_by     String?
approved_at     Timestamp?
rejected_by     String?
rejected_at     Timestamp?
created_at      Timestamp
updated_at      Timestamp
```

### 3.11 `cash_transactions`

```text
id                  String
type                String  enum: cash_in | cash_out
amount              double
reference           String
pnl_category        String  enum: revenue | cogs | expenses | worker_cost | other
description         String?
worker_id           String?
worker_payment_id   String?
status              String  enum: pending | approved
approved_by         String?
approved_at         Timestamp?
created_at          Timestamp
updated_at          Timestamp
```

### 3.12 `cash_approvals`

```text
id              String
transaction_id  String
amount          double
type            String   (mirrors cash_transaction.type)
reference       String
status          String   enum: pending | approved | rejected
approved_by     String?
notes           String?
created_at      Timestamp
updated_at      Timestamp
```

### 3.13 `expense_approvals`

```text
id              String
expense_id      String
amount          double
category        String
description     String
status          String   enum: pending | approved | rejected
approved_by     String?
notes           String?
created_at      Timestamp
updated_at      Timestamp
```

### 3.14 `pnl_snapshots`

```text
id (= period)   String   YYYY-MM
period          String
revenue         double
cogs            double
gross_profit    double
expenses        double
worker_cost     double
net_profit      double
updated_at      Timestamp
```

Written only by Cloud Functions via Admin SDK. Flutter never writes to this collection.

### 3.15 `suppliers`

```text
id                String
name              String
contact_name      String
phone             String
email             String?
address           String?
payment_terms     String
total_purchased   double
last_order_at     Timestamp?
active            bool
created_at        Timestamp
updated_at        Timestamp
```

### 3.16 `purchase_orders`

```text
id                    String
supplier_id           String
supplier_name         String
items                 List<Map>  [{product_id, product_name, sku, size, qty, unit_cost}]
total                 double
status                String  enum: draft | sent | partially_received | received | closed | cancelled
expected_delivery     Timestamp?
inventory_batch_id    String?  (set by Cloud Function on received)
received_at           Timestamp?
notes                 String?
created_by            String
created_at            Timestamp
updated_at            Timestamp
```

### 3.17 `qc_records`

```text
id              String
batch_id        String
product_id      String
passed_qty      int
rejected_qty    int
worker_id       String?
rejected_items  List<Map>  [{inventory_item_id, size, reason}]
notes           String?
inspector       String  (uid)
created_at      Timestamp
```

### 3.18 `waste_records`

```text
id                  String
qc_record_id        String
batch_id            String
product_id          String?
size                String?
inventory_item_id   String?
worker_id           String?
reason              String
disposed            bool
disposed_at         Timestamp?
created_at          Timestamp
```

### 3.19 `settings`

```text
id                  "global"
company_name        String
currency_primary    String  default: SAR
currency_secondary  String  default: PKR
tax_rate            double
low_stock_threshold int
logo_url            String?
updated_at          Timestamp
```

### 3.20 `order_returns`

```text
id                    String
order_id              String
customer_id           String
customer_name         String   (denormalized)
type                  String   enum: full_return | partial_return | replacement | damage_claim
items                 List<Map>
                        [ { order_item_id, product_id, product_name, size,
                            qty_returned (int, always in pairs),
                            condition (good | damaged),
                            reason (wrong_size | stitching_issue | sole_defect | wrong_item | cosmetic | other) } ]
total_qty_returned    int
refund_amount         double
replacement_order_id  String?  (set when a replacement dispatch is created)
notes                 String?
status                String   enum: pending | approved | rejected | completed
approved_by           String?
approved_at           Timestamp?
created_by            String
created_at            Timestamp
updated_at            Timestamp
```

### 3.21 `shops`

```text
id                String
name              String
area              String
city              String
address           String?
latitude          double?
longitude         double?
phone             String?
contact_name      String?
seller_id         String?   (assigned seller)
seller_name       String?   (denormalized)
notes             String?
active            bool
created_by        String
created_at        Timestamp
updated_at        Timestamp
```

Location pinning: latitude + longitude stored for each shop so sellers
(and replacement sellers covering another seller's market) can navigate
to all assigned shops. Coordinates viewable as Google Maps link.

Qty units are always pairs (int). Standard pack sizes: 12 pairs (dozen) and 20 pairs.
Cash/refund entry is created manually by manager via `/cash` after physical refund confirmed.
This collection is never written to from `pnl_snapshots` — no P&L auto-entries on return.

---

## 4. Cloud Functions

| File | Trigger | Summary |
| --- | --- | --- |
| `onOrderCreated.js` | `orders/{id}` onCreate | Status → processing |
| `onOrderItemAdded.js` | `order_items/{id}` onCreate | Reserve inventory_items, decrement stock |
| `onCashApproved.js` | `cash_approvals/{id}` onUpdate→approved | Update pnl_snapshots revenue / expenses |
| `onExpenseApproved.js` | `expense_approvals/{id}` onUpdate→approved/rejected | Update pnl_snapshots expenses |
| `onWorkerPaymentCreated.js` | `worker_payments/{id}` onCreate | Increment total_earned, update pnl_snapshots worker_cost |
| `onQCReject.js` | `qc_records/{id}` onCreate | Create waste_records, update batch status |
| `onInventoryBatchComplete.js` | `inventory_batches/{id}` onUpdate→complete | Calc cost_per_pair, stamp items, update stock |
| `onPurchaseOrderReceived.js` | `purchase_orders/{id}` onUpdate→received | Create inventory_items + batch from PO |
| `onReturnApproved.js` | `order_returns/{id}` onUpdate→approved | Restock good items, write waste for damaged, mark order_items returned |

---

## 5. Flutter Screens — 36 Routes

| Route | Screen File | Min Role |
| --- | --- | --- |
| `/login` | `login_screen.dart` | public |
| `/` | `dashboard_screen.dart` | viewer |
| `/products` | `products_list_screen.dart` | viewer |
| `/products/new` | `product_form_screen.dart` | manager |
| `/products/:id` | `product_detail_screen.dart` | viewer |
| `/inventory` | `inventory_batch_list_screen.dart` | viewer |
| `/inventory/new` | `inventory_batch_form_screen.dart` | manager |
| `/inventory/:id` | `inventory_batch_detail_screen.dart` | viewer |
| `/orders` | `orders_list_screen.dart` | viewer |
| `/orders/new` | `order_form_screen.dart` | manager |
| `/orders/:id` | `order_detail_screen.dart` | viewer |
| `/customers` | `customers_list_screen.dart` | viewer |
| `/customers/new` | `customer_form_screen.dart` | manager |
| `/customers/:id` | `customer_detail_screen.dart` | viewer |
| `/workers` | `workers_list_screen.dart` | manager |
| `/workers/new` | `worker_form_screen.dart` | admin |
| `/workers/:id` | `worker_detail_screen.dart` | manager |
| `/workers/:id/pay` | `worker_payment_form_screen.dart` | manager |
| `/expenses` | `expenses_list_screen.dart` | viewer |
| `/expenses/new` | `expense_form_screen.dart` | manager |
| `/cash` | `cash_screen.dart` | manager |
| `/approvals` | `approvals_screen.dart` | admin |
| `/purchase-orders` | `purchase_orders_list_screen.dart` | viewer |
| `/purchase-orders/new` | `purchase_order_form_screen.dart` | manager |
| `/purchase-orders/:id` | `purchase_order_detail_screen.dart` | viewer |
| `/suppliers` | `suppliers_list_screen.dart` | viewer |
| `/suppliers/new` | `supplier_form_screen.dart` | manager |
| `/suppliers/:id` | `supplier_detail_screen.dart` | viewer |
| `/shops` | `shops_list_screen.dart` | viewer |
| `/shops/new` | `shop_form_screen.dart` | manager |
| `/shops/:id` | `shop_detail_screen.dart` | viewer |
| `/returns` | `returns_list_screen.dart` | viewer |
| `/returns/new` | `return_form_screen.dart` | manager |
| `/returns/:id` | `return_detail_screen.dart` | viewer |
| `/qc` | `qc_screen.dart` | manager |
| `/waste` | `waste_screen.dart` | viewer |
| `/pnl` | `pnl_screen.dart` | viewer |
| `/reports` | `reports_screen.dart` | manager |
| `/settings` | `settings_screen.dart` | admin |

---

## 6. Multi-Agent Orchestration

Orchestrator reads this file, assigns work to sub-agents. Each sub-agent runs independently and reads this file first.

| Sub-Agent | Responsibility | Output Files |
| --- | --- | --- |
| core-agent | pubspec.yaml, main.dart, app.dart, router, theme, constants, validators, formatters | `app/lib/core/**`, `app/lib/main.dart`, `app/lib/app.dart` |
| models-agent | All 20 Dart model classes | `app/lib/models/*.dart` |
| auth-agent | Auth provider, user model, login screen | `app/lib/providers/auth_provider.dart`, `app/lib/screens/login_screen.dart` |
| financial-providers-agent | pnl, expenses, cash, approvals providers | `app/lib/providers/pnl_*.dart`, `app/lib/providers/expense_*.dart` |
| ops-providers-agent | products, inventory, orders, customers, workers, suppliers, POs, QC, waste, returns providers | `app/lib/providers/*.dart` |
| dashboard-pnl-agent | Dashboard + P&L + Reports screens | `app/lib/screens/dashboard_screen.dart`, `pnl_screen.dart`, `reports_screen.dart` |
| products-inventory-agent | Product + Inventory screens | `app/lib/screens/products_*.dart`, `inventory_*.dart` |
| orders-customers-agent | Orders + Customers + Returns screens | `app/lib/screens/orders_*.dart`, `customers_*.dart`, `returns_*.dart`, `return_*.dart` |
| workers-financial-agent | Workers + Expenses + Cash + Approvals screens | `app/lib/screens/workers_*.dart`, `expense_*.dart`, `cash_screen.dart`, `approvals_screen.dart` |
| ops-screens-agent | POs + Suppliers + QC + Waste + Settings screens | `app/lib/screens/purchase_order_*.dart`, `supplier_*.dart`, `qc_screen.dart`, `waste_screen.dart`, `settings_screen.dart` |
| widgets-agent | AppShell nav, StatCard, RoleGuard, shared form widgets | `app/lib/widgets/*.dart` |

**Sub-agent constraints:**

1. Import only packages from section 2
2. Use only collection name constants from `Collections` class
3. All Firestore writes via provider notifiers — never from screen/widget
4. All timestamps: `Timestamp.now()` from cloud_firestore
5. All role checks: use `RoleGuard` widget or inline `userModel.role` check
6. Never write to `pnl_snapshots` from Dart
7. Approved `worker_payments` are read-only — never allow edit/delete in UI
8. Completed `order_returns` are read-only — status `completed` locks the document
9. All list screens: `limit(50)`, paginate with `startAfterDocument`

---

## 7. P&L Architecture

```text
Dashboard reads ONE doc: pnl_snapshots[YYYY-MM]  →  6 KPI cards

P&L screen reads 12 docs: pnl_snapshots[YYYY-01..YYYY-12]  →  bar chart

Cloud Functions WRITE to pnl_snapshots when:
  - cash_approval approved  →  +revenue or +expenses
  - expense_approval approved  →  +expenses
  - worker_payment created (approved)  →  +worker_cost
  All functions recalculate:
    gross_profit = revenue - cogs
    net_profit   = gross_profit - expenses - worker_cost

Returns do NOT auto-write to pnl_snapshots.
Cash refund is logged manually via /cash screen by manager.
```

---

## 8. Development Commands

```bash
# Deploy security rules first
firebase deploy --only firestore:rules,firestore:indexes

# Deploy functions
cd functions && npm install
firebase deploy --only functions

# Flutter setup
cd app && flutter pub get
cd app && flutter run -d chrome

# After adding riverpod annotations
cd app && dart run build_runner build --delete-conflicting-outputs

# Run all tests
cd app && flutter test

# Full production deploy
firebase deploy
```

---

## 9. Completion Tracker

| Layer | Status |
| --- | --- |
| AGENTS.md | done |
| CLAUDE.md | done |
| firestore.rules | done |
| firestore.indexes.json | done |
| firebase.json + .firebaserc | done |
| Cloud Functions (9 total) | done |
| Flutter pubspec + entry files | done |
| Core (router, theme, constants) | done |
| 20 Dart models | done |
| Riverpod providers | done |
| 36 screens | done |
| Shared widgets | done |
| Test suite (25 unit + widget tests) | done |
| Returns / replacements module | done |
| User management (settings admin section) | done |
| xlsx export on all 10 list screens | done |
| Security audit: role guards on all form screens | done |
| R3 compliance: no direct Firestore/Storage in screens | done |
| Cloud Functions P&L optimization (FieldValue.increment) | done |
| PO received: batched writes (>500 item support) | done |
| Android release build config (keystore + signing) | done |

---

## 10. Firestore Composite Indexes (Required)

Every query combining `.where()` on one field and `.orderBy()` on a different field requires a composite index in `firestore.indexes.json`. Missing indexes cause empty lists with no error in UI.

**Always deploy after any change:** `firebase deploy --only firestore:indexes`

**Full required index table (20 total):**

| Collection | Field 1 | Field 2 | Notes |
| --- | --- | --- | --- |
| workers | active ASC | name ASC | workersProvider |
| orders | customer_id ASC | created_at DESC | ordersByCustomerProvider |
| orders | status ASC | created_at DESC | ordersListProvider filter |
| order_items | order_id ASC | created_at DESC | orderItemsProvider |
| inventory_items | inventory_batch_id ASC | status ASC | batch item status filter |
| inventory_items | product_id ASC | status ASC | product item status filter |
| inventory_items | inventory_batch_id ASC | created_at ASC | inventoryItemsByBatchProvider |
| inventory_batches | status ASC | created_at DESC | qcPendingBatchesProvider |
| worker_payments | worker_id ASC | created_at DESC | workerPaymentsProvider |
| expenses | status ASC | created_at DESC | expensesProvider filter |
| expense_approvals | status ASC | created_at DESC | expenseApprovalsProvider |
| cash_approvals | status ASC | created_at DESC | cashApprovalsProvider |
| cash_transactions | type ASC | created_at DESC | cashTransactionsProvider |
| waste_records | worker_id ASC | created_at DESC | wasteRecordsProvider |
| purchase_orders | supplier_id ASC | created_at DESC | purchaseOrdersProvider |
| qc_records | batch_id ASC | created_at DESC | qcRecordsProvider |
| products | active ASC | created_at DESC | productsProvider |
| suppliers | active ASC | name ASC | suppliersProvider |
| order_returns | status ASC | created_at DESC | orderReturnsProvider |
| order_returns | order_id ASC | created_at DESC | orderReturnsByOrderProvider |
| shops | active ASC | name ASC | shopsProvider |
| shops | seller_id ASC, active ASC | name ASC | shopsBySellerProvider |

**Rule:** Every time a new StreamProvider adds `.where(fieldA).orderBy(fieldB)` where `fieldA ≠ fieldB`, add the corresponding composite index to `firestore.indexes.json` before deploying.

---

## 11. User Management

User accounts are managed by admin users inside the **Settings screen** (`/settings`) — there is NO separate `/users` route.

- **Location:** Settings screen → "User Accounts" section (admin-only, wrapped in `RoleGuard`)
- **Provider:** `allUsersProvider` (stream) + `UserManagementNotifier` (writes) in `user_provider.dart`
- **Create user:** Uses a secondary Firebase App (`Firebase.initializeApp(name: 'secondary_...')`) to avoid signing out the currently logged-in admin
- **Fields:** display_name, email, password, role (admin/manager/viewer/worker_pk/worker_ksa), optional worker_id
- **Activate/deactivate:** Sets `active: false` on the Firestore `users` doc; Firestore rules must check `active == true` for all authenticated requests
- **Worker link:** worker_pk and worker_ksa roles can be linked to a `workers` doc via `worker_id` field
