---
name: apk-build-signing
description: "Use when: building release APK, managing signing keys, CI/CD setup, version bumping, split-per-ABI builds, ProGuard rules, Android permission audits."
---

# Skill: Android APK Build, Signing & Release Management

## Version Convention
```yaml
# pubspec.yaml
version: MAJOR.MINOR.PATCH+BUILD
# e.g., 3.0.0+7
# MAJOR: breaking changes / major feature releases
# MINOR: new features, backward compatible
# PATCH: bug fixes
# BUILD: internal build counter (always increment on every release)
```

**Tool to bump version:** `dart tool/bump_version.dart` (already in repo)

## Release Build Command
```bash
# ── CANONICAL BUILD (always use fat APK) ──────────────────────────────────
# Fat APK — single universal file, direct sideload to any device.
cd app
flutter build apk --release

# Output location:
# build/app/outputs/flutter-apk/app-release.apk

# ── Web ───────────────────────────────────────────────────────────────────
flutter build web --release
firebase deploy --only hosting

# ── NEVER use --split-per-abi — project standard is fat APK only ──────────
# (split-per-abi is for Play Store; this app is sideloaded)

# App Bundle (Play Store only — NOT the standard for this project)
# flutter build appbundle --release
```

## Signing Configuration
**Key file location:** `app/android/key.properties` (NOT committed to git)
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=../app-keystore.jks
```

**In build.gradle.kts:**
```kotlin
android {
  signingConfigs {
    create("release") {
      val keyProps = Properties().apply {
        load(rootProject.file("key.properties").inputStream())
      }
      keyAlias = keyProps["keyAlias"] as String
      keyPassword = keyProps["keyPassword"] as String
      storeFile = file(keyProps["storeFile"] as String)
      storePassword = keyProps["storePassword"] as String
    }
  }
  buildTypes {
    release {
      signingConfig = signingConfigs.getByName("release")
      isMinifyEnabled = true
      isShrinkResources = true
      proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
  }
}
```

## ProGuard Rules for ShoesERP
```proguard
# proguard-rules.pro — additions for current dependencies
# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Firestore
-keep class com.google.cloud.firestore.** { *; }

# flutter_riverpod / dart reflection
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# JSON serialization
-keep class * implements java.io.Serializable { *; }

# printing (pdf)
-keep class com.github.gunnaraa.** { *; }

# share_plus
-keep class dev.fluttercommunity.plus.share.** { *; }
```

## Android Permissions Audit
Current permissions in `AndroidManifest.xml` — verify only necessary:
```xml
<!-- Required -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- For PDF share/download -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />

<!-- For notifications -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- For image picker -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />

<!-- NOT needed (remove if present): -->
<!-- android.permission.CAMERA — not used, image picker can work without it -->
<!-- android.permission.ACCESS_FINE_LOCATION — not needed for route-based ERP -->
```

## Approval Cycles & Shared Installation Issues
Problem spotted in user's request: "breaking changes in APK regarding approval cycles and shared installations"

### Shared Installation Patterns
When multiple technicians/sellers use the same device:
- Firebase Auth sign-in/out handles user switching
- Ensure `signOut()` clears ALL local state:
  ```dart
  Future<void> signOut() async {
    // 1. Invalidate all providers
    _invalidateRoleScopedProviders();
    // 2. Clear SharedPreferences 
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // 3. Sign out Firebase
    await _ref.read(firebaseAuthProvider).signOut();
  }
  ```
- Issue: If seller A signs out and seller B signs in, Riverpod providers may cache seller A's data
- Fix: `_invalidateRoleScopedProviders()` must invalidate ALL family providers

### APK Uninstall Cleanup
To clean all app data on uninstall:
```xml
<!-- AndroidManifest.xml -->
<!-- Android automatically clears app data on uninstall -->
<!-- Make sure no data is written outside app directories: -->
<!-- /data/data/[package]/ — auto-cleared ✅ -->
<!-- /sdcard/ — persists after uninstall unless explicitly cleaned -->
<!-- Fix: Use getExternalFilesDir() (auto-cleared) instead of getExternalStorageDirectory() -->
```

In Dart (flutter):
```dart
// Use app-specific external storage (auto-cleared on uninstall)
final dir = await getApplicationDocumentsDirectory(); // auto-cleared
// NOT: await getExternalStorageDirectory() on Android < 10
```

### Version Upgrade Breaking Changes Checklist
When releasing a new version to devices with existing data:
- [ ] Schema changes in Firestore: all new fields have defaults in `fromJson()`
- [ ] New required keys in `l10n` files checked for all 3 languages
- [ ] SharedPreferences key changes: add migration or default in `getOrNull()`
- [ ] Firebase index changes: deploy before app update reaches users
- [ ] Firestore rules changes: deploy before app update

## CI/CD (Manual Github Actions Setup)
```yaml
# .github/workflows/build.yml
name: Flutter Build
on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.x'
      - name: Install dependencies
        run: cd app && flutter pub get
      - name: Analyze
        run: cd app && flutter analyze lib --no-pub
      - name: Test
        run: cd app && flutter test -r expanded
      - name: Build APK
        run: cd app && flutter build apk --release --split-per-abi
```

## Minimum SDK Targets
```kotlin
// build.gradle.kts
android {
  defaultConfig {
    minSdk = 21           // Android 5.0+ (covers 99%+ devices)
    targetSdk = 36        // Android 16 (tested on Samsung A56)
    compileSdk = 36
  }
}
```

## Device Compatibility Matrix
| Device | Android | API | Status |
|--------|---------|-----|--------|
| Samsung A56 | 16 | 36 | ✅ Verified |
| V2247 | 14 | 34 | ✅ Verified |
| Generic ARMv7 | 5+ | 21+ | Should work |
