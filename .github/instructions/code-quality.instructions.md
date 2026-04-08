---
applyTo: "app/lib/**/*.dart"
---

# Code Quality Standards

## Vibe-Coded Debt Signals (Red Flags → Required Fix)

| Pattern | Risk | Fix |
|---------|------|-----|
| `// TODO` in production files | Deferred bug/feature | File issue, complete in current PR or remove comment |
| Raw collection string in `.collection('transactions')` | Collection drift | Replace with `Collections.transactions` |
| `FirebaseFirestore.instance` in screens/widgets | Broken write guard | Move to provider notifier |
| `Colors.white` or `Colors.grey[X]` hardcoded | Dark mode regression | Use `Theme.of(context).colorScheme.*` or `AppBrand.*` |
| `EdgeInsets.only(left: X)` | RTL regression | Replace with `EdgeInsetsDirectional.only(start: X)` |
| `print(` or `debugPrint(` | Credential/stack leak | Use `logger.d/w/e(` via `Logger` |
| `await batch.commit()` outside try/catch | Unhandled Firestore error | Wrap in `AsyncValue.guard` or catch + `AppErrorMapper` |

## Dead Code Detection

A provider with zero consumers (no `ref.watch` or `ref.read` in any file except its own definition) is dead code. Before shipping:

```bash
# Find providers with no references outside their defining file
# (manual check — search for provider name across lib/)
grep -r "myProvider" app/lib/ | grep -v "myProvider ="
```

Zero references outside the definition file → candidate for removal.

## Orphan Widget Detection

A widget class defined in a file but never imported/used is dead code. Check for zero `import` references to the file outside itself.

## Pre-Commit 5-Check Gate

Run before every commit touching Dart files:

1. `flutter analyze lib --no-pub` → "No issues found!"
2. `flutter test -r compact` → all pass
3. `grep -rn "\.collection('" app/lib/ | grep -v Collections\.` → zero matches
4. Version in `pubspec.yaml` == version in `app_brand.dart`
5. All added L10n keys present in EN, AR, UR

## Breakage Chain Reference

### Chain 1: Admin SA Key Change
SA key in Firestore `admin_config/sa_credentials` → `AdminIdentityService._getOrLoadCreds()` → cache cleared by `clearCache()` on sign-out → `_getAccessToken()` with scope `cloud-platform` → 3-step VERIFY_EMAIL.

**When key changes:** Update Firestore doc → call `clearCache()` → test Send Verification.

### Chain 2: New Firestore Field
New field on model → `fromJson` default value → `toJson` include → `copyWith` → Firestore rules create/update allow → `firestore.indexes.json` if queried → write tests for round-trip + default.

**Checklist:** All 6 steps before committing.

### Chain 3: Role String Change
Role string in `users` doc → `user_model.dart` getter (`isAdmin`, `isSeller`) → `firestore.rules` `isAdminRole()` regex → app write normalization → test all 3 in alignment.

**Current canonical roles:** `admin`, `seller` (maps: `manager` → admin-equivalent in rules, normalized on write).

### Chain 4: Collection Rename
`Collections.*` constant value → `firestore.rules` match path → `firestore.indexes.json` collection field → all 5 docs synced → re-deploy rules + indexes.

## Provider Write Guard Checklist

Before every `batch.commit()`:
```dart
// ✅ Identity field validation
final normalizedCreatedBy = createdBy.trim();
if (normalizedCreatedBy.isEmpty) throw ArgumentError('createdBy must not be empty');
if (routeId.trim().isEmpty) throw ArgumentError('routeId must not be empty');
// ... then batch.commit()
```

Required for: `created_by`, `route_id`, `shop_id`, `seller_id`, `product_id`.

## Collections.* Usage

Every `.collection()` call uses a constant. Zero exceptions. CI gate enforces this.

## Writes in Providers Only

All Firestore writes go through provider notifiers. Screens call notifier methods. No `FirebaseFirestore.instance` in screens or widgets.

## OWASP Mobile Top 10 Compliance Baseline

- M3 (Insecure Auth): Firebase Auth + Firestore rules enforce access, not just app-side guards
- M4 (Injection): `AppSanitizer.sanitize()` on all user-visible text before Firestore write
- M7 (Client-Side Auth): Admin checks in provider submit methods, not only in router guards
- M9 (Insecure Data Storage): No sensitive data in SharedPreferences; SA key only in Firestore
