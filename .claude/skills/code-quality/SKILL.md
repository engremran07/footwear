---
name: code-quality
description: "Use when: detecting dead code, auditing vibe-coded debt, enforcing pre-commit hygiene gates, OWASP Mobile baseline compliance, or reviewing breakage chain risks before committing."
---

# Skill: Code Quality for ShoesERP

## Purpose
Prevent drift between layers (rules, app, docs) through automated hygiene gates
and a recognizable catalog of vibe-coded debt signals.

## Vibe-Coded Debt Signal Table

| Pattern | Signal | Correct Pattern |
|---------|--------|----------------|
| `db.collection('inventory_transactions')` | Raw collection string | `db.collection(Collections.inventoryTransactions)` |
| `if (user.isSeller && ...)` gating stock source | Admin silently excluded | Use `sellerInventoryProvider(user.id)` for all roles |
| `.where('deleted', isEqualTo: false)` | Excludes field-missing docs | Client-side `d.data()['deleted'] != true` |
| `ref.read(provider)` inside `build()` | Stale data guarantee | `ref.watch(provider)` |
| `flutter build apk --release --split-per-abi` | Wrong APK split | `flutter build apk --release` (fat APK) |
| Hardcoded `Colors.red`, `Colors.white` | Theme breakage in dark mode | `AppBrand.errorFg`, `AppBrand.errorBg`, etc. |
| `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` | Unstyled raw SnackBar | `errorSnackBar()` / `successSnackBar()` helpers |

## 4 Canonical Breakage Chains

### Chain 1: Collection Rename
`collections.dart` rename → providers break → rules break → indexes stale  
**Fix order:** constants.dart → providers → rules → indexes → `firebase deploy --only firestore:rules,firestore:indexes`

### Chain 2: Auth Provider Leak
New admin-data provider added → not in `_invalidateRoleScopedProviders()` → seller inherits admin data after logout  
**Fix:** Check `auth_provider.dart::_invalidateRoleScopedProviders` after every new provider.

### Chain 3: Firestore Rules + App Role Mismatch
Rules accept 'admin'; app writes 'Admin' → all admin writes fail with `permission-denied`  
**Fix:** `isAdminRole()` regex in rules + `role.trim().toLowerCase()` before every Firestore write.

### Chain 4: Composite Index Gap
`where(A) + orderBy(B)` query added → no index → list renders empty with no error message  
**Fix:** Add entry to `firestore.indexes.json` → redeploy.

### Chain 5: Transitive Dep Wasm Lock
A pub package locks a shared transitive dep (e.g. `archive`) to an old major version → `flutter build web --release` emits `avoid_double_and_int_checks lint violation` FROM a different package that cannot upgrade past the lock.  
**Diagnosis:**
1. `flutter pub deps --style=list` → find who pulls in the violating package
2. `flutter pub outdated` → find the version constraint blocking the upgrade
3. Check pub changelog for the violating package for "Wasm" / "archive" keywords
4. Find the parent that locks the shared transitive dep to the old range
**Fix order:** Replace or upgrade the blocking package. Never force-override `archive` major version — it compiles but breaks caller package API at runtime.  
**PowerShell gotcha:** `flutter build web --release` appears to exit code 1 via PowerShell `NativeCommandError` even on a clean Wasm build. Check `$LASTEXITCODE` explicitly; exit 0 = real success even when Wasm dry-run messages appear.

## Five Non-Negotiable Pre-Commit Checks

```bash
# 1. flutter analyze (must be zero issues)
cd app && flutter analyze lib --no-pub

# 2. flutter test (all must pass)
flutter test -r expanded

# 3. No raw collection strings
grep -rn "\.collection('" lib/ | grep -v "Collections\."

# 4. No direct Firestore writes in screens/widgets
grep -rn "FirebaseFirestore\|\.doc(\|\.collection(" lib/screens/ lib/widgets/

# 5. No split-per-abi in scripts/workflows
grep -rn "split-per-abi" ../ --include="*.{yml,yaml,md,sh}"
```
All five checks must return zero violations before any commit.

## Dead Code Detection

```bash
# Find provider files with zero usages
grep -rL "import.*$(basename $file .dart)" app/lib/ --include="*.dart"

# Find unused constants
grep -rn "static const String" app/lib/core/constants/ | \
  while read line; do
    key=$(echo $line | grep -o "'[^']*'" | head -1)
    count=$(grep -rn "$key" app/lib/ | wc -l)
    [ "$count" -lt 2 ] && echo "UNUSED: $line"
  done
```

## OWASP Mobile Top 10 Baseline

| Risk | Control in ShoesERP |
|------|---------------------|
| M1 Improper Credential Usage | Keystore secrets in `key.properties` (gitignored), no hardcoded secrets |
| M2 Inadequate Supply Chain Security | `flutter pub outdated` before each release; ProGuard enabled |
| M3 Insecure Authentication | Firebase Auth + session guard (8h hard limit, 15min inactivity) |
| M4 Insufficient Input/Output Validation | `AppSanitizer._s()` on all PDF interpolation; URL HTTPS validation |
| M5 Insecure Communication | Firebase SDK enforces TLS; no plaintext HTTP endpoints |
| M6 Inadequate Privacy Controls | No PII in logs; Crashlytics strips user data |
| M7 Insufficient Binary Protections | ProGuard + minify + shrink enabled in `build.gradle.kts` |
| M8 Security Misconfiguration | Firestore deny-by-default; `isValidRole()` regex in rules |
| M9 Insecure Data Storage | No local DB with sensitive data; Firestore encrypted at rest |
| M10 Insufficient Cryptography | Auth tokens managed by Firebase SDK; no custom crypto |
