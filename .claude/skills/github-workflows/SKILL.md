---
name: github-workflows
description: "Use when: creating or updating GitHub Actions workflows for Flutter builds, Firebase deploys, hygiene gates, APK signing, monotonic versionCode checks, or CI/CD self-healing patterns."
---

# Skill: GitHub Actions Workflows for ShoesERP

## Workflow Inventory

| File | Trigger | Purpose |
|------|---------|---------|
| `.github/workflows/ci.yml` | push / PR | Analyse + test + 17 hygiene gates |
| `.github/workflows/build-apk.yml` | workflow_dispatch | Debug + release fat APK |
| `.github/workflows/release.yml` | push tag `v*` | Full validate + build + deploy + GitHub Release |
| `.github/workflows/deploy-web.yml` | push to main | Flutter web build + Firebase Hosting deploy |

## Concurrency Cancel-in-Progress Pattern
Every workflow that touches Firebase must cancel stale runs:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Monotonic versionCode Guard

```bash
CURRENT_CODE=$(grep '^version:' app/pubspec.yaml | grep -oP '\+\K\d+')
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0+0")
LAST_CODE=$(echo "$LAST_TAG" | grep -oP '\+\K\d+' || echo "0")
if [ "$CURRENT_CODE" -le "$LAST_CODE" ]; then
  echo "ERROR: versionCode $CURRENT_CODE must be > last tag $LAST_CODE"
  exit 1
fi
```

## 17 Hygiene Gate Grep Patterns

```bash
# Gate 1: No raw collection strings
if grep -rn "\.collection('" app/lib/ | grep -v "Collections\."; then
  echo "FAIL: Raw collection strings found"
  exit 1
fi

# Gate 2: allTransactionsProvider in invalidation list
if ! grep -q "allTransactionsProvider" app/lib/providers/auth_provider.dart; then
  echo "FAIL: allTransactionsProvider missing from _invalidateRoleScopedProviders"
  exit 1
fi

# Gate 3: No split-per-abi
if grep -rn "split-per-abi" .github/ app/ --include="*.{yml,yaml,sh}"; then
  echo "FAIL: split-per-abi detected — use fat APK only"
  exit 1
fi

# Gate 4: No direct Firestore writes in screens/widgets
if grep -rn "FirebaseFirestore\|\.collection(" app/lib/screens/ app/lib/widgets/ 2>/dev/null; then
  echo "FAIL: Direct Firestore write in screen/widget"
  exit 1
fi

# Gate 5: L10n parity (EN keys == AR keys == UR keys)
python3 - <<'EOF'
import re, sys
src = open("app/lib/core/l10n/app_locale.dart").read()
en = set(re.findall(r"'(\w+)':", re.search(r"case 'en'.*?};", src, re.S).group()))
ar = set(re.findall(r"'(\w+)':", re.search(r"case 'ar'.*?};", src, re.S).group()))
ur = set(re.findall(r"'(\w+)':", re.search(r"case 'ur'.*?};", src, re.S).group()))
missing_ar = en - ar; missing_ur = en - ur
if missing_ar or missing_ur:
    print(f"FAIL: L10n gaps — AR missing: {missing_ar}, UR missing: {missing_ur}")
    sys.exit(1)
print("L10n parity OK")
EOF

# Gate 6: No PDF generation on main thread
if grep -rn "buildPdf\|PdfDocument\|pw\.Document" app/lib/ | grep -v "Isolate\.run\|compute("; then
  echo "FAIL: PDF generation not offloaded to isolate"
  exit 1
fi

# Gate 16: Firestore rules and indexes files present and valid
if [ ! -f "firestore.rules" ] || [ ! -f "firestore.indexes.json" ]; then
  echo "FAIL: firestore.rules or firestore.indexes.json missing"
  exit 1
fi
python3 -c "import json,sys; json.load(open('firestore.indexes.json'))" || {
  echo "FAIL: firestore.indexes.json is not valid JSON"; exit 1
}
echo "firestore.rules and firestore.indexes.json present and valid"

# Gate 17: No temp/debug artifacts tracked
FOUND=$(git ls-files | grep -E "auth-users\.json|check_locale\.(ps1|py)|debug\.log|\.flag$" || true)
if [ -n "$FOUND" ]; then
  echo "FAIL: temp/debug artifact tracked: $FOUND"; exit 1
fi
```

## Mandatory Local Pre-Signoff Sequence (non-bypassable)

Before every commit, ALL of the following must succeed and evidence quoted:

| Step | Command | Required evidence |
| --- | --- | --- |
| 1 | `flutter analyze lib --no-pub` | `No issues found!` |
| 2 | `dart analyze test/` | `No issues found!` |
| 3 | `flutter test -r expanded` | `All N tests passed!` |
| 4 | Hygiene gates 4a-4f | all zero results |
| 5 | `markdownlint "**/*.md" ...` | zero output (exit 0) |
| 6 | `firebase deploy --only firestore:rules,firestore:indexes` | `Deploy complete!` |
| 7 | `flutter build web --release` | `EXIT: 0` |
| 8 | `firebase deploy --only hosting` | `Deploy complete!` |
| 9 | `flutter build apk --release` | file size quoted |
| 10 | `git log --oneline -5` + `git status --short` | no unexpected artifacts |
| 11 | `git add -A && git commit && git push` | commit hash + push output |
| 12 | `adb install -r <apk>` (if connected) | `Success` |


When `firebase_options.dart` is gitignored, CI must generate a stub:

```bash
echo "class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'test', appId: 'test', messagingSenderId: '0',
    projectId: 'test', storageBucket: '');
}" > app/lib/firebase_options.dart
```

Or use FlutterFire CLI with `FIREBASE_TOKEN` secret:
```yaml
- run: dart pub global activate flutterfire_cli
- run: flutterfire configure --project=${{ vars.FIREBASE_PROJECT_ID }} --yes
  env:
    FIREBASE_TOKEN: ${{ secrets.FIREBASE_CLI_TOKEN }}
```

## APK Signing Secrets Pattern

```yaml
- name: Decode keystore
  run: |
    echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > app/android/app/footwear-erp.jks
    cat > app/android/key.properties <<EOF
    storePassword=${{ secrets.KEYSTORE_PASSWORD }}
    keyPassword=${{ secrets.KEY_PASSWORD }}
    keyAlias=${{ secrets.KEY_ALIAS }}
    storeFile=../app/footwear-erp.jks
    EOF
```

**Required GitHub secrets:**
- `KEYSTORE_BASE64` — base64-encoded JKS file
- `KEYSTORE_PASSWORD` — store password
- `KEY_PASSWORD` — key password  
- `KEY_ALIAS` — key alias (e.g. `footwear-erp`)
- `FIREBASE_CLI_TOKEN` — `firebase login:ci` output
- `FIREBASE_SERVICE_ACCOUNT` — service account JSON (for google-github-actions/auth)
