---
name: inline-audit
description: "Use when: fixing any issue, gap, or error in ShoesERP. This skill enforces a mandatory inline audit of every affected subsystem while the primary fix is being applied. The agent acts as a flying inspector — fix what was asked, but also catch and fix any culprit found while reading the touched files."
---

# Skill: Inline Audit & Fix Workflow

## Philosophy
Every change is also an audit pass. When you open a file to fix one thing, you
are obligated to scan the file for related violations. Leave the code better
than you found it — but never over-engineer.

## Mandatory Audit Layers (check every time)

### 1. Role/Rules Alignment
| Check | Source |
|-------|--------|
| `isAdmin` / `isSeller` / `canHaveSellerInventory` getters match Firestore rule helpers | `user_model.dart` vs `firestore.rules` |
| `isAdminRole()` / `isSellerRole()` regex in rules matches all in-flight role strings | `firestore.rules` |
| Admin-as-seller paths: admin can write their own `seller_inventory` docs | `firestore.rules`, `product_provider.dart` |

### 2. Collection Alignment
Every Firestore collection reference must use `Collections.*` constants, never
raw strings.

```dart
// ✅ Correct
db.collection(Collections.inventoryTransactions)
// ❌ Wrong
db.collection('inventory_transactions')
```

### 3. Audit Log Routing
| Operation | Must write to |
|-----------|--------------|
| Warehouse → seller transfer | `inventory_transactions` (type: `transfer_out`) |
| Seller → warehouse return | `inventory_transactions` (type: `return_to_warehouse`) |
| Sale invoice stock deduction | `seller_inventory` (quantity decrement via batch) |
| Cash in/out | `transactions` |
| Invoice lifecycle | `invoices` |

**Never write inventory movement audit logs to `transactions`.**

### 4. Query → Rule → Index Triangle
For every new or modified Firestore query:
1. Confirm `firestore.rules` allows the query for the expected role
2. Confirm `firestore.indexes.json` has the composite index
3. For `where(A) + orderBy(B)` where A ≠ B → MUST have composite index

### 5. Provider Write Guard Pattern
All Firestore writes go through provider notifiers, never screens/widgets
directly. Before submitting any form:
- Required identity fields (`created_by`, `seller_id`, `route_id`) must be
  non-empty — validate before batch.commit()
- Admin operations: validate `adminId.trim().isNotEmpty`

### 6. Deleted-Field Visibility
Old documents (pre-DI-01 audit) have NO `deleted` field. Never use:
```dart
// ❌ Silently excludes docs where field doesn't exist
.where('deleted', isEqualTo: false)
```
Always use client-side:
```dart
// ✅ Catches both {deleted: false} and missing-field docs
.where((d) => d.data()['deleted'] != true)
```

### 7. Build Hygiene

- Always fat APK: `flutter build apk --release` — NEVER `--split-per-abi`
- `app/pubspec.yaml` version == `AppBrand.appVersion + '+' + AppBrand.buildNumber`
- After touching any user-visible feature: bump PATCH+BUILD, rebuild both APK and web

### 8. Mandatory Release Sequence (non-bypassable, every session)

```powershell
# Step 1 — analyze
flutter analyze lib --no-pub          # quote "No issues found!"
dart analyze test/                    # quote "No issues found!"
flutter test -r expanded              # quote "All N tests passed!"
# Step 2 — deploy Firestore (ALWAYS, not just on rules change)
firebase deploy --only firestore:rules,firestore:indexes   # quote "Deploy complete!"
# Step 3 — web build + hosting deploy
$ErrorActionPreference='Continue'; flutter build web --release; Write-Host "EXIT: $LASTEXITCODE"
firebase deploy --only hosting        # quote "Deploy complete!"
# Step 4 — APK build
flutter build apk --release           # quote file size
# Step 5 — commit audit + push
git log --oneline -5                  # review; no unexpected commits
git status --short                    # no unexpected artifacts
git add -A ; git commit -m "type: summary — vX.Y.Z+N"   # quote hash
git push                              # quote branch + hash
# Step 6 — device install (if device connected)
adb devices
adb -s <device-id> install -r "D:\Footwear\app\build\app\outputs\flutter-apk\app-release.apk"  # quote "Success"
```

Any step skipped = **incomplete session**. Next agent MUST check `git log`
before starting new work and complete all missing steps first.

## Inline Audit Checklist (run mentally on every PR)

```
[ ] Collections constants used everywhere (no raw strings)
[ ] Inventory audit logs go to inventory_transactions, not transactions
[ ] No isValidTransactionType violation (only: cash_out, cash_in, return, payment, write_off)
[ ] Deleted-field filter is client-side !=true
[ ] Every where(A)+orderBy(B) query has composite index
[ ] Admin-as-seller paths: sellerId/sellerName always populated in invoice submit
[ ] Fat APK build command in all scripts/docs
[ ] version bumped in pubspec.yaml AND app_brand.dart
[ ] Every transaction/invoice write also updates shop.balance atomically in same batch
[ ] No screen/widget writes directly to transactions, invoices, or shop.balance
```

## Known Failure Signatures (inline audit catches these)

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Transfer history empty after transfer | audit log in `transactions` not `inventory_transactions` | Move write to `Collections.inventoryTransactions` |
| Seller rule violation on admin batch | `isValidTransactionType` excludes custom types | Use approved types or write to `inventory_transactions` |
| Old tx invisible in customer detail | `where(deleted==false)` excludes field-missing docs | Client-side `!=true` filter |
| Admin sees no items in invoice screen | admin inventory async hardcoded to empty | `ref.watch(sellerInventoryProvider(user.id))` for all |
| Invoice created with no items | `user.isSeller &&` guard bypassed for admin | Remove role guard; check `deductions.isEmpty` for all |
| Fat APK not installed, wrong ABI file | build used `--split-per-abi` | Always `flutter build apk --release` |
| Stale balance after dev flush | transactions deleted via console/CLI without updating shop.balance | Run `node dev_reset.js` from repo root after any manual flush |
| `avoid_double_and_int_checks` in `flutter build web` | Transitive dep (image 4.3.0) locked by another pkg (excel) to old archive | Upgrade or replace blocking package; see Chain 5 in CLAUDE.md |
| `flutter build web --release` exit 1, `Built build/web` still printed | PowerShell interprets Wasm dry-run stderr as error | Check `$LASTEXITCODE` in PowerShell; 0 = real success |

## 4 Canonical Breakage Chains

### Chain 1: Collection Rename
Collection constant renamed → providers break → rules break → indexes stale  
**Fix order:** constants.dart → providers → rules → indexes → deploy

### Chain 2: Auth Provider Leak
Provider added that reads admin-only data → not in `_invalidateRoleScopedProviders` → seller loads stale admin data after logout  
**Fix:** Grep new providers; add to `_invalidateRoleScopedProviders()` in `auth_provider.dart`

### Chain 3: Firestore Rules + App Role Mismatch
Rules accept 'admin' only → app writes 'Admin' (capitalized) → every admin write fails  
**Fix:** `isAdminRole()` regex in rules + `trim().toLowerCase()` on all app role writes

### Chain 4: Composite Index Gap
Provider adds `where(A) + orderBy(B)` → no composite index → list empty with no UI error  
**Fix:** Add index to `firestore.indexes.json` → deploy with `firebase deploy --only firestore:indexes`

## Hygiene Grep Gate (run before any commit)

```bash
# 1. No raw collection strings
grep -rn "\.collection('" app/lib/ | grep -v "Collections\."
# Expected: zero matches

# 2. allTransactionsProvider must be in invalidation list
grep -n "allTransactionsProvider" app/lib/providers/auth_provider.dart
# Expected: at least 1 match

# 3. No split-per-abi
grep -rn "split-per-abi" . --include="*.{yml,yaml,md,sh}"
# Expected: zero matches (historical docs excluded)

# 4. No direct Firestore writes in screens
grep -rn "FirebaseFirestore\|\.doc(\|\.collection(" app/lib/screens/
# Expected: zero matches

# 5. Fat APK only
grep -rn "flutter build apk" . --include="*.{yml,yaml,md,sh}"
# Expected: all lines use --release, none use --split-per-abi
```

## AGENTS.md Update Rule
When this skill catches and fixes a new issue, add it to **AGENTS.md Section 10**
audit history in the same commit/change set.
