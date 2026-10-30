---
name: apk-build-signing
description: "Use when: diagnosing Android Gradle builds, building or signing ShoesERP APK/AAB releases, preparing Play Console uploads, managing release version codes, or installing APKs on devices."
---

# Android Release Builds, Signing, and Gradle

## Verified ShoesERP Android Baseline

| Component | Current configuration |
| --- | --- |
| Flutter | 3.47.8 |
| Java / Kotlin JVM target | 17 |
| Gradle build JDK | 17 or 21; the current workstation runs 21 |
| Gradle wrapper | 9.3.1 |
| Android Gradle Plugin | 9.1.0 |
| Kotlin Android plugin | 2.4.0 |
| Google Services plugin | 4.5.0 |
| Compile / target SDK | 36 |
| Minimum SDK | 29 |
| Application ID | `footwear.com.pk` |

Use the checked-in Gradle wrapper. Do not install a separate Gradle version or
upgrade the Android and Kotlin plugins independently of the wrapper. The app
module applies the Android and Kotlin plugins before the Flutter Gradle plugin.
Release builds require signing configuration and fail closed when it is absent.

These are the compatibility-verified versions for Flutter 3.47.8, not a claim
that each is the newest version published independently. Flutter 3.47.8's
Android templates use Gradle 9.3.1, AGP 9.1.0, and Kotlin Gradle Plugin 2.4.0.
Firebase's Android Google Services setup currently documents plugin 4.5.0.
Do not move beyond the Flutter-tested Gradle/AGP/Kotlin range without checking
the Flutter tool's compatibility data and building both APK and AAB tasks.

The version alignment is material: the resolved Firebase Auth Android
artifact can publish Kotlin 2.4.0 metadata, which Kotlin Gradle Plugin 2.2.20
cannot read. Raise the Kotlin plugin to at least the metadata version and keep
Gradle and AGP within the Flutter-compatible matrix.

## Version and Android Version-Code Rules

The Flutter version is `MAJOR.MINOR.PATCH+BUILD`. Update
`app/pubspec.yaml`, `app/lib/core/constants/app_brand.dart`, and the
trilingual top entry in `app/lib/core/data/changelog_data.dart` together.
Verify the exact matching values before building:

```powershell
Select-String -Path "app\pubspec.yaml","app\lib\core\constants\app_brand.dart" -Pattern '^version:|appVersion|buildNumber'
```

`app/android/app/build.gradle.kts` encodes Android `versionCode` as a compact,
monotonic sequence anchored immediately above the latest accepted Play code:

```text
androidVersionCodeBase + buildNumber
```

Keep the base synchronized between `AppBrand.androidVersionCodeBase` and the
Gradle `computeAndroidVersionCode` function. The current base is
`310190000`, anchored to the prior Play upload `310191130`; source build
`1132` therefore produces Play bundle code `310191132`. Do not reset the code
to a low semantic version such as `0.0.1`, reuse a code, or encode the whole
semantic version into increasingly large digits. Increment the Flutter build
number for each Play upload and verify that the generated AAB code is greater
than the latest accepted Play code. The function checks positivity and Play
Console's `2,100,000,000` maximum. The Android package/version regression test
checks the Dart and Gradle bases together. Flutter adds ABI-specific offsets
to split APKs, so compare the base AAB code with Play history and each APK
against the highest distributed APK code.

## Play In-App Updates and Password Autofill

The Android release build uses flexible Play In-App Updates for routine
releases. Play priority `4` or higher and the Remote Config parameter
`minimum_supported_version_code` can require an update; the Remote Config
default is `0`, so no minimum-version gate is active until an owner configures
it. Raise that value only after the required version is available to every
intended distribution channel. The gate is Android-release-only, and Play's
update API must be validated with a Play-installed build; sideloaded builds
cannot establish Play update availability. If Play is unavailable, the
minimum-version gate remains visible with a Play Store recovery link.

Login fields expose Android username/email and password autofill hints. The
app submits the platform autofill context only after successful Firebase
Authentication. It does not read, save, or store passwords itself and does
not add another authentication mechanism.

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

If Flutter reports that a Windows engine artifact is in use while preparing
the SDK, classify this as an SDK/cache file lock, not a Gradle compatibility
failure. Inspect active Flutter test/debug processes and release the lock by
stopping the owning run through its IDE or test runner. Do not terminate an
unrelated process or delete/replace the shared SDK artifact. Retry
`flutter doctor -v` and the original Flutter command after the owning run has
closed; until then, Dart-only package inspection is not evidence that Flutter
tests or Android builds work.

For the Windows `icudtl.dat` “user-mapped section open” error, do not mistake
the accompanying download/extract wording for proof of a network failure.
Flutter may need to validate or replace engine artifacts before `pub get`.
Run only one Flutter SDK/artifact operation at a time; stop overlapping
Flutter tests, debug runs, desktop runs, or another SDK update gracefully
through the IDE or test runner, then wait for the SDK file to be released.
Use Resource Monitor's Associated Handles search or Windows Restart Manager
to identify a current owner when needed; Dart language-server processes alone
are not proof that they own the locked artifact. Do not kill processes by
name, disable antivirus, or delete the Flutter cache. Retry the original
command once the file is no longer locked. If the owner cannot be identified
or the error persists without a lock, investigate endpoint protection and
network access separately.

`flutter pub get --no-example` completed successfully on 2026-10-28 after
four logged `icudtl.dat` lock failures; a later verification also completed
with `Got dependencies!` and exit code 0. No Flutter test/debug process was
found owning the artifact during that verification, and Restart Manager
reported no current owner. The five packages reported as newer but
incompatible are resolver constraints, not a failed `pub get`; do not force
overrides to silence that notice.

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

### Windows verification notes

- `gradlew.bat --version` reports Gradle's embedded Kotlin runtime; it is not
  the Android Kotlin Gradle plugin version. Verify the plugin pin in
  `app/android/settings.gradle.kts` before diagnosing version drift.
- `apkanalyzer` expects APK/APK-set inputs and may fail on an AAB with
  `NoSuchFileException: /AndroidManifest.xml`. Do not treat that as a bundle
  build/signing failure. Use `bundletool` when available for AAB manifest
  inspection; otherwise report that bundle metadata was not independently
  extracted and verify the synchronized source version plus JAR signature.
- A successful release build with unaccepted SDK licenses is evidence only
  that the local build completed. Do not accept licenses automatically.
- `jarsigner -verify` may report `jar verified.` while warning that a private
  upload certificate chain is not trusted by the local JVM. Treat that as
  signature-integrity evidence, not proof that Play Console recognizes the
  upload key; confirm the certificate is registered before upload.
- When the VS Code Gradle extension reports a Gradle, AGP, or Kotlin version
  different from `gradle-wrapper.properties` and `settings.gradle.kts`, do not
  upgrade the project again based on that extension log. Confirm the checked-in
  wrapper directly, refresh the Gradle project in VS Code, and reload the
  window so task discovery uses the current project model. Recheck the version
  banner before treating an extension task failure as a release-build failure.
- A `this and base files have different roots` error while the Gradle extension
  creates a Flutter plugin source task is distinct from APK/AAB compilation.
  First compare the extension's reported Gradle/plugin versions with the
  checked-in wrapper and settings, then reproduce through `gradlew.bat` using
  the exact task. If the current wrapper reproduces a cross-volume path error,
  keep the existing Pub cache intact and configure a new `PUB_CACHE` on the
  same volume as the workspace. From the Flutter app directory:

  ```powershell
  $repoDrive = (Get-Location).Drive.Root
  $cachePath = Join-Path $repoDrive 'FlutterPubCache'
  [Environment]::SetEnvironmentVariable('PUB_CACHE', $cachePath, 'User')
  $env:PUB_CACHE = $cachePath
  flutter pub get --no-example
  Set-Location android
  .\gradlew.bat :flutter_plugin_android_lifecycle:compileDebugUnitTestSources --stacktrace
  ```

  Restart VS Code and its Gradle server after changing the user environment so
  the extension inherits `PUB_CACHE`. Re-run the exact failed task before
  retrying APK/AAB builds. Do not copy or delete the old cache, relocate build
  outputs, or change project versions to work around this filesystem error.

## Local Validation and Release Artifacts

Release actions are separate: local builds do not deploy Hosting or Firestore,
and do not commit or push. User authorization is required for those operations.
For app changes, first run relevant tests and analyzers. PDF-capable commands
must retain `--dart-define=use_arabic=true`.

When a release changes Firestore Rules or the client write schema, a successful
local build does not prove production compatibility. Do not describe the
artifact as production-ready or use it for authenticated business-flow
acceptance until the matching Rules are deployed with explicit authorization.
Keep local Rules tests, local artifacts, production deployment, and device
installation as separately reported gates.

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

For Play Console track selection, upload-key validation, and compliant launch
marketing, follow the
[Google Play release and marketing skill](../google-play-release-marketing/SKILL.md).
Do not upload an AAB until its signing-certificate fingerprint is confirmed
against the Play Console upload certificate.

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

## Gradle Failure Evidence

Do not report that “all Gradle issues are fixed” from a configuration review or
a successful unrelated task. The current version inventory is a compatibility
baseline, not proof that every APK/AAB task succeeds on every workstation.
When a build fails:

1. Capture the exact Flutter command, task, exit code, first Gradle exception,
   and underlying `Caused by` chain. Include `flutter doctor -v`, `java
   -version`, and `gradlew.bat --version` when toolchain mismatch is plausible.
2. Classify the failure before editing: dependency/DNS resolution, SDK/license,
   signing, memory/resources, filesystem/cache, plugin configuration, source
   compilation, or task-specific APK/AAB packaging.
3. Re-run the narrow failing task after a root-cause change, then run both APK
   and AAB release tasks when the change affects shared Android configuration.
   Do not upgrade or clear caches merely to turn a single failed build green.
4. Report exactly which tasks ran and their output. A clean APK is not evidence
   that the AAB task works, and an AAB signature check is not proof that Play
   Console accepts the upload certificate.

Verified 2026-10-28: Firebase Auth metadata 2.4.0 failed with Kotlin Gradle
Plugin 2.2.20. The verified Flutter 3.47.8 toolchain is Gradle 9.3.1, AGP
9.1.0, and Kotlin Gradle Plugin 2.4.0; Google Services is 4.5.0. AGP 9 also
requires the public `ApplicationExtension` DSL and Kotlin's typed
`compilerOptions` instead of the deprecated `BaseAppModuleExtension` and
`android.kotlinOptions` APIs in this app. The split APK task completed after
that migration. Flutter still warns that the app and current Firebase
plugins apply Kotlin Gradle Plugin; retain and report this upstream warning
instead of suppressing it. The split APKs and 72.1 MB AAB then built. The AAB
reported `jar verified.` but also a self-signed/untrusted local certificate
chain and no timestamp; this is not evidence that Play Console accepts the
upload key. The subsequent v3.10.13+1124 delivery copied and installed the
ARM64 APK successfully, then deployed Rules/indexes and Hosting.

The cross-volume Gradle source-root failure was independently reproduced
through the checked-in wrapper. A same-drive user-level `PUB_CACHE` made the
exact `:flutter_plugin_android_lifecycle:compileDebugUnitTestSources` task
succeed again (`BUILD SUCCESSFUL in 55s`). The split APK, AAB, and web release
tasks then all completed. This resolves the reported workstation failure; it
does not guarantee builds on different cache, SDK, or network configurations.

For large workspaces, build release artifacts sequentially and inspect free
memory before starting. Never stop unrelated processes or delete shared caches
to address resource pressure. If no reproducible failure is available, record
the toolchain baseline and leave the issue unverified rather than inventing a
Gradle fix.

Verified 2026-10-28: the VS Code Gradle server initially reported Gradle 8.14,
AGP 8.11.1, and Kotlin 2.2.20, then failed while creating
`:flutter_plugin_android_lifecycle:compileDebugUnitTestSources` because the
app build output was on `D:\` and the plugin source was in the Pub cache on
`C:\`. The checked-in wrapper/settings specify Gradle 9.3.1, AGP 9.1.0, and
Kotlin 2.4.0. The exact task also failed through the current wrapper with that
cross-volume cache layout. Resolving packages with `PUB_CACHE` on the workspace
volume made the exact task pass: `BUILD SUCCESSFUL in 2m` (29 actionable
tasks). The existing C-drive cache was left untouched. The user-level
`PUB_CACHE` was set to the same-drive cache; restart VS Code before verifying
the Gradle extension. APK/AAB release builds remain separate verification
gates.
