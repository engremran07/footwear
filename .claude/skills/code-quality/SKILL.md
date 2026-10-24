---
name: code-quality
description: "Use when: detecting dead code, auditing vibe-coded debt, enforcing pre-commit hygiene gates, OWASP Mobile baseline compliance, or reviewing breakage chain risks before committing."
---

# Skill: Code Quality for ShoesERP

## Purpose

Prevent drift between layers (rules, app, docs) through automated hygiene gates
and a recognizable catalog of vibe-coded debt signals.

## Invocation and required inputs

Use when implementing or reviewing a ShoesERP change that crosses app,
provider, Rules, index, test, or documentation boundaries. Read the touched
implementation and authoritative runtime contracts before running checks.

## Workflow and output

Identify only the relevant debt signals, run scoped hygiene checks, and report
findings with file/line evidence and exact command results. Do not treat a
pattern match as proof of a defect without reading its call site and
surrounding contract.

## Dependencies and boundaries

Use `AGENTS.md` and `CLAUDE.md` as runtime authorities. This skill does not
authorize release operations; follow the scope-aware validation and explicit
authorization rules there.

## Validation

Run the checks relevant to changed code. Use Firestore Rules Emulator tests for
Rules changes and local analyzers/tests for app changes. Do not deploy Rules,
build a release, commit, or push unless explicitly authorized.

## Vibe-Coded Debt Signal Table

| Pattern | Signal | Correct Pattern |

|---------|--------|----------------|

| `db.collection('inventory_transactions')` | Raw collection string | `db.collection(Collections.inventoryTransactions)` |

| `if (user.isSeller && ...)` gating stock source | Admin silently excluded | Use `sellerInventoryProvider(user.id)` for all roles |

| `.where('deleted', isEqualTo: false)` | Excludes field-missing docs | Client-side `d.data()['deleted'] != true` |

| `ref.read(provider)` inside `build()` | Stale data guarantee | `ref.watch(provider)` |

| `flutter build apk --release --split-per-abi` | Correct Android release artifact path | `flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true` |

| Unscoped literal colors on theme-sensitive screen surfaces | Possible contrast/theme drift | Prefer `Theme.of(context).colorScheme` or the semantic `AppTheme`/`AppBrand` value; allow literals when explicitly paired with a surface and verified |

| `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` | Unstyled raw SnackBar | `errorSnackBar()` / `successSnackBar()` helpers |

## 4 Canonical Breakage Chains

### Chain 1: Collection Rename

`collections.dart` rename → providers break → rules break → indexes stale  
**Fix order:** constants.dart → providers → rules → indexes → Rules Emulator tests. Deploy Rules/indexes only when the user explicitly authorizes production deployment.

### Chain 2: Auth Provider Leak

New admin-data provider added → not in `_invalidateRoleScopedProviders()` → seller inherits admin data after logout  
**Fix:** Check `auth_provider.dart::_invalidateRoleScopedProviders` after every new provider.

### Chain 3: Firestore Rules + App Role Mismatch

Rules accept 'admin'; app writes 'Admin' → all admin writes fail with `permission-denied`  
**Fix:** `isAdminRole()` regex in rules + `role.trim().toLowerCase()` before every Firestore write.

### Chain 4: Composite Index Gap

`where(A) + orderBy(B)` query added → no index → list renders empty with no error message  
**Fix:** Add an entry to `firestore.indexes.json` and validate the query/rule path locally. Deploy only when explicitly authorized.

### Chain 5: Transitive Dep Wasm Lock

A pub package locks a shared transitive dep (e.g. `archive`) to an old major version → `flutter build web --release` emits `avoid_double_and_int_checks lint violation` FROM a different package that cannot upgrade past the lock.  
**Diagnosis:**

1. `flutter pub deps --style=list` → find who pulls in the violating package

2. `flutter pub outdated` → find the version constraint blocking the upgrade

3. Check pub changelog for the violating package for "Wasm" / "archive" keywords

4. Find the parent that locks the shared transitive dep to the old range
**Fix order:** Replace or upgrade the blocking package. Never force-override `archive` major version — it compiles but breaks caller package API at runtime.  
**PowerShell gotcha:** `flutter build web --release` appears to exit code 1 via PowerShell `NativeCommandError` even on a clean Wasm build. Check `$LASTEXITCODE` explicitly; exit 0 = real success even when Wasm dry-run messages appear.

## Focused Code-Change Checks

```bash

# 1. flutter analyze (must be zero issues)

cd app && flutter analyze lib --no-pub

# 2. flutter test (all must pass)

flutter test -r expanded --dart-define=use_arabic=true

# 3. No raw collection strings

grep -rn "\.collection('" lib/ | grep -v "Collections\."

# 4. No direct Firestore writes in screens/widgets

grep -rn "FirebaseFirestore\|\.doc(\|\.collection(" lib/screens/ lib/widgets/

# 5. Release scripts document the canonical ABI split (when release files change)
grep -rn "flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true" ../ --include="*.{yml,yaml,md,sh}"

```

Run checks relevant to the edited scope. A release build, deployment, commit, or
push is a separate operation and requires explicit user authorization.

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

| M3 Insecure Authentication | Firebase Auth plus active-profile, role, tenant, and selected-workspace Rules checks; no app-managed device/session gate |

| M4 Insufficient Input/Output Validation | `AppSanitizer._s()` on all PDF interpolation; URL HTTPS validation |

| M5 Insecure Communication | Firebase SDK enforces TLS; no plaintext HTTP endpoints |

| M6 Inadequate Privacy Controls | No PII in logs; Crashlytics strips user data |

| M7 Insufficient Binary Protections | ProGuard + minify + shrink enabled in `build.gradle.kts` |

| M8 Security Misconfiguration | Firestore deny-by-default; `isValidRole()` regex in rules |

| M9 Insecure Data Storage | No local DB with sensitive data; Firestore encrypted at rest |

| M10 Insufficient Cryptography | Auth tokens managed by Firebase SDK; no custom crypto |
