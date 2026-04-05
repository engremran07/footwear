---
name: security-owasp-mobile
description: "Use when: hardening app security, auditing Firebase rules, preventing injection, securing PDF export, validating auth tokens, reviewing OWASP Mobile Top 10 compliance."
---

# Skill: OWASP Mobile Security + Firebase Hardening

## OWASP Mobile Top 10 (2024) Compliance for ShoesERP

### M1 — Improper Credential Usage
- ✅ No API keys in source code — Firebase config via `firebase_options.dart` (legitimate)
- ✅ No hardcoded admin passwords
- ⚠️ `firebase_options.dart` is committed to git — acceptable for Firebase (client config is public), but verify API key restrictions in Firebase console
- Action: Restrict Firebase API key to Android/iOS app package only in Google Cloud Console

### M2 — Inadequate Supply Chain Security
- ⚠️ 62 packages have newer versions incompatible with constraints — run `flutter pub outdated` regularly
- Action: Pin critical security-sensitive packages: `firebase_auth`, `cloud_firestore`, `firebase_core`
- Action: Review each major version upgrade for breaking security changes

### M3 — Insecure Authentication
- ✅ Firebase Auth (email/password) — proper token refresh
- ✅ `authStateProvider` stream drives all auth flows
- ✅ Secondary `FirebaseApp` approach for user creation (no admin SDK needed)
- ⚠️ No MFA (multi-factor authentication) for admin role
- ⚠️ No session timeout notification to user before 8h admin hard limit
- Action: Show warning dialog at 7h30m for admin users

### M4 — Insufficient Input/Output Validation
- ✅ `AppSanitizer` and `AppValidators` used in forms
- ✅ PDF export uses `_s()` sanitizer (S-08) for text interpolation
- ✅ `docSizeOk()` in Firestore rules prevents large doc abuse
- ⚠️ Invoice total vs items sum NOT validated at provider level (only UI)
- Action: Add server-side validation in `InvoiceNotifier.createInvoice()` before batch commit

### M5 — Insecure Communication
- ✅ All Firebase communication uses TLS (HTTPS)
- ✅ No custom network calls outside Firebase SDK
- ✅ `cached_network_image` for external product images (HTTPS URLs expected)
- ⚠️ No URL validation for product `image_url` field — could accept `http://` (insecure)
- Action: Validate `image_url` starts with `https://` in ProductFormScreen and provider

### M6 — Inadequate Privacy Controls
- ✅ No biometrics or sensitive hardware access
- ✅ Minimal permissions: only notifications + storage for PDF
- ⚠️ Customer data (name, balance, phone) stored in Firestore without encryption at rest
- Firebase Firestore encrypts at rest by default ✅
- ⚠️ `SharedPreferences` stores `auth.remember_me` — acceptable (no tokens stored)

### M7 — Insufficient Binary Protections
- ✅ ProGuard/R8 configured (`proguard-rules.pro` exists)
- ✅ Split-per-ABI APK builds
- ⚠️ `android:debuggable` must be `false` in release build — verify in `build.gradle.kts`
- Action: Confirm `buildTypes.release.debuggable = false`

### M8 — Security Misconfiguration
- ✅ `firestore.rules` deployed with deny-by-default
- ✅ `storage.rules` exists (though Storage is not used)
- ✅ `firebase_app_check` dependency included — verify AppCheck is enforced in rules
- ⚠️ AppCheck enforcement: if AppCheck is in debug mode in release builds, rules bypass is possible
- Action: Verify AppCheck is in production mode for release APK

### M9 — Insecure Data Storage
- ✅ No sensitive data in `SharedPreferences` beyond `auth.remember_me`
- ✅ No local SQLite or unencrypted local storage
- ✅ PDF files generated in-memory (Isolate.run) and shared via share_plus, not persisted
- ⚠️ `path_provider` used for download helper — verify temp files are cleaned up after share

### M10 — Insufficient Cryptography
- ✅ No custom cryptography — uses Firebase's managed encryption
- ✅ Base64 for logo is encoding, not encryption — acceptable for non-secret data

## Firebase Rules Hardening Checklist
```javascript
// Already in rules — verify these are deployed:
// ✅ deny-by-default (no match = denied)
// ✅ isActiveUser() check on all reads
// ✅ docSizeOk() on all writes
// ✅ withinWriteRate() on user updates
// ✅ isAdminRole() with regex (case-insensitive, trim-tolerant)
// ✅ isSellerForRoute() prevents cross-route writes
// ✅ Bootstrap admin create is one-time (checks !exists())

// AUDIT ITEM: transactions.update — sellers can update ANY field on their own tx
// Current rule: isAdmin() || (isSeller() && created_by == uid)
// Risk: seller could update amount, route_id, etc. after creation
// Recommendation: sellers should only update limited fields:
allow update: if isAdmin() ||
  (isSeller() && resource.data.created_by == request.auth.uid &&
   request.resource.data.diff(resource.data).affectedKeys()
     .hasOnly(['status', 'notes', 'updated_at']));
```

## PDF Security (S-08 Compliance)
- ✅ `_s()` sanitizer strips control chars + collapses whitespace
- ✅ No string interpolation with raw user input in PDF widgets
- ✅ `Isolate.run()` isolates PDF generation from main thread

## URL Injection Prevention
```dart
// Product image URL validation:
String? validateImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return 'Invalid URL';
  if (uri.scheme != 'https') return 'Only HTTPS URLs allowed';
  return null;
}
```

## Input Sanitization at Provider Layer
```dart
// In InvoiceNotifier.createInvoice() — before batch write:
if (invoice.items.isNotEmpty) {
  final computedSubtotal = invoice.items.fold<double>(0, (s, i) => s + i.subtotal);
  if ((computedSubtotal - invoice.subtotal).abs() > 0.01) {
    throw AppException('Invoice totals are inconsistent');
  }
}
if (invoice.amountReceived > invoice.total + 0.01) {
  throw AppException('Amount received exceeds invoice total');
}
```

## Session Security
- 8h admin hard session limit (AppLifecycleListener) — ALREADY IMPLEMENTED
- ⚠️ Warning dialog missing at 7h30m
- ⚠️ Seller sessions: no timeout (intentional — sellers operate for full working days)

## Android Release Checklist
- [ ] `debuggable = false` in release buildType
- [ ] ProGuard rules include Firebase, Riverpod, gson
- [ ] `firebase_app_check` in production mode (not debug)
- [ ] No `console.log` / `Logger` calls in release build (use `kReleaseMode` guard)
- [ ] Signing keystore stored outside source tree (key.properties not committed)
