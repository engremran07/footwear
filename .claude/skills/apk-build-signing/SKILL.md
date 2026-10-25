---
name: apk-build-signing
description: "Use when: diagnosing Android Gradle builds, building or signing ShoesERP APK/AAB releases, preparing Play Console uploads, managing release version codes, or installing APKs on devices."
---

# Android Release Builds, Signing, and Gradle

## Verified ShoesERP Android Baseline

| Component | Current configuration |
| --- | --- |
| Flutter | 3.41.6 |
| Java / Kotlin JVM target | 17 |
| Gradle build JDK | 17 or 21; the current workstation runs 21 |
| Gradle wrapper | 8.14 |
| Android Gradle Plugin | 8.11.1 |
| Kotlin Android plugin | 2.2.20 |
| Google Services plugin | 4.4.2 |
| Compile / target SDK | 36 |
| Minimum SDK | 29 |
| Application ID | `footwear.pk.com` |

Use the checked-in Gradle wrapper. Do not install a separate Gradle version or
upgrade the Android and Kotlin plugins independently of the wrapper. The app
module applies the Android and Kotlin plugins before the Flutter Gradle plugin.
Release builds require signing configuration and fail closed when it is absent.

## Version and Android Version-Code Rules

The Flutter version is `MAJOR.MINOR.PATCH+BUILD`. Update
`app/pubspec.yaml`, `app/lib/core/constants/app_brand.dart`, and the
trilingual top entry in `app/lib/core/data/changelog_data.dart` together.
Verify the exact matching values before building:

```powershell
Select-String -Path "app\pubspec.yaml","app\lib\core\constants\app_brand.dart" -Pattern '^version:|appVersion|buildNumber'
```

`app/android/app/build.gradle.kts` encodes the Android `versionCode` as:

```text
major * 100,000,000 + minor * 1,000,000 + patch * 10,000 + buildNumber
```

The component bounds and Play Console's `2,100,000,000` maximum are checked
before Gradle configures the release. This encoding keeps version segments
ordered and prevents a newer semantic version from generating a lower code
than a historical install. Confirm the built APK/AAB version metadata when
changing this formula. Flutter adds an ABI-specific offset to split APK
version codes; for example, the ARM64 APK may be higher than the base code
used by the AAB. Compare the APK against the highest previously distributed
code rather than assuming every ABI APK has the same code.

## Signing Configuration

The release signing file is `app/android/key.properties`; it is local,
gitignored configuration. The Gradle build reads its keystore path, alias,
and passwords from that file. Never print, copy, commit, or place signing
values in Dart defines, source, logs, CI output, or this skill. The referenced
keystore must exist at the path configured locally. Do not generate a fallback
debug-signed release.

The same release signing configuration signs both the split APKs and the
Android App Bundle. Google Play App Signing should be enabled in Play Console;
the uploaded AAB is signed with the registered upload key.

## Diagnose Before Changing Gradle

From PowerShell:

```powershell
Set-Location D:\Footwear\app
flutter doctor -v
java -version
Set-Location android
.\gradlew.bat --version
```

Then reproduce the failure with the Flutter command that produced it and
inspect the first Gradle exception and its cause. Do not change dependencies,
plugin versions, cache directories, or signing setup to mask a DNS, proxy,
SDK-license, memory, or filesystem error. A missing remote artifact caused by
DNS is not evidence that the dependency version is incompatible. Avoid
`flutter clean` unless stale generated output is part of the demonstrated
failure; it does not repair a version or network mismatch.

If `flutter doctor` reports unaccepted Android SDK licenses, ask the device
owner to review and accept them with `flutter doctor --android-licenses`.
Release builds that already succeed do not justify silently accepting legal
terms on the owner's behalf.

Before release builds, check signing-file presence without printing its
contents:

```powershell
Test-Path "android\key.properties"
```

Use Gradle's wrapper for diagnostics and Flutter's build commands for release
artifacts. When Windows reports memory pressure, run one release build at a
time and close unnecessary applications rather than deleting caches or
terminating unrelated processes.

## Local Validation and Release Artifacts

Release actions are separate: local builds do not deploy Hosting or Firestore,
and do not commit or push. User authorization is required for those operations.
For app changes, first run relevant tests and analyzers. PDF-capable commands
must retain `--dart-define=use_arabic=true`.

From `D:\Footwear`:

```powershell
Set-Location app
flutter analyze lib --no-pub
dart analyze test/
flutter test -r expanded --dart-define=use_arabic=true
```

Build the phone-delivery split-per-ABI APK set:

```powershell
flutter build apk --release --split-per-abi --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true
```

Canonical outputs:

```text
build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk
build\app\outputs\flutter-apk\app-x86_64-release.apk
build\app\outputs\flutter-apk\app-release.apk
```

Build the signed Play Console bundle:

```powershell
flutter build appbundle --release --dart-define=USE_PLAY_INTEGRITY=true --dart-define=use_arabic=true
```

The upload artifact is:

```text
build\app\outputs\bundle\release\app-release.aab
```

An AAB is for Play Console upload and cannot be installed directly. Install a
matching APK on devices. Verify the release artifacts and report their exact
paths and sizes:

The module's ABI split setting is enabled for APK builds and disabled when a
`bundle` Gradle task is requested. Android Gradle Plugin rejects app bundles
when multiple shrunk-resource APK outputs are configured in the same task.
Keep this task-aware distinction and rebuild both requested artifacts after
changing it.

```powershell
apksigner verify --verbose "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
jarsigner -verify "build\app\outputs\bundle\release\app-release.aab"
Get-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk","build\app\outputs\bundle\release\app-release.aab" | Select-Object FullName,Length
```

## Copy and Install the Phone APK

Check for an authorized, connected device before copying or installing:

```powershell
adb devices
```

Copy the ARM64 delivery APK to Downloads and install the same verified host
artifact:

```powershell
$apk = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
adb push $apk /sdcard/Download/app-arm64-v8a-release.apk
adb install --streaming -r $apk
```

If `adb devices` lists no device, report the exact output and skip device
delivery. Do not uninstall an existing app to work around a version-code or
signing mismatch; diagnose the package metadata and certificate instead.

## Release Checklist

- [ ] Version in `pubspec.yaml`, `AppBrand`, and changelog is synchronized.
- [ ] Tests and both Dart analyzers pass with quoted output.
- [ ] The release signing configuration is present without exposing values.
- [ ] Split APK and signed AAB are built from the same source and version.
- [ ] APK and AAB signatures verify; artifact paths and sizes are recorded.
- [ ] ADB device availability is checked before phone delivery.
- [ ] Rules/indexes, Hosting, commit, push, and Play Console publication are
      performed only when separately authorized.

## Android Permission Review

Review the actual `app/android/app/src/main/AndroidManifest.xml` and plugin
requirements whenever permissions change. Keep only permissions needed by
current workflows. Do not add camera, location, storage, boot, or notification
permissions based on this skill alone; test the relevant Android API levels
and document any user-visible permission prompt.
