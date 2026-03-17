# ShoesERP

A production-grade footwear business ERP system built with Flutter + Firebase.

## Modules

| Module | Description |
| --- | --- |
| Dashboard | KPI overview — revenue, profit, orders, stock |
| P&L | Monthly P&L from pre-aggregated snapshots |
| Products | Shoe SKU catalog management |
| Inventory | Batch production tracking + individual pair stock |
| Orders | Customer order lifecycle |
| Customers | Buyer profiles |
| Workers (PK) | Pakistan production worker payroll |
| Workers (KSA) | Saudi Arabia warehouse worker payroll |
| Expenses | Categorized expense approval workflow |
| Cash | Cash in/out with approval and P&L tracking |
| Approvals | Unified approval queue (cash + expenses) |
| Purchase Orders | Supplier POs with receiving workflow |
| Suppliers | Vendor management |
| QC | Quality control per inventory batch |
| Waste | QC-rejected pair tracking |
| Returns | Customer return / replacement / damage claim workflow |
| Reports | Analytics and exports |
| Settings | Company config, users, roles |

## Stack

- **Frontend**: Flutter 3.x (Android + iOS + Web)
- **State**: Riverpod + go_router
- **Backend**: Firebase (Firestore + Auth + Cloud Functions Node.js 20)

## Quick Start

```bash
# 1. Configure Firebase
# Install FlutterFire CLI: dart pub global activate flutterfire_cli
# flutterfire configure --project=YOUR_PROJECT_ID

# 2. Install app dependencies
cd app && flutter pub get

# 3. Deploy security rules FIRST
firebase deploy --only firestore:rules

# 4. Deploy Cloud Functions
cd functions && npm install
firebase deploy --only functions

# 5. Run the app
cd app && flutter run -d chrome
```

## Development Order

1. `firestore.rules` — deploy before any app code
2. Cloud Functions — all 9 functions
3. Data models (20 Dart classes)
4. Riverpod providers
5. Screens and widgets

See [AGENTS.md](AGENTS.md) for full architecture details.  
See [CLAUDE.md](CLAUDE.md) for AI coder instructions.
