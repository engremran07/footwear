---
name: user-management
description: "Use when: creating, editing, or deleting users; role assignment; password reset; auth/Firestore user profile alignment."
---

# Skill: User Management

## Domain
Firebase Auth + Firestore user profiles for admin/seller roles in ShoesERP.

## Key Files
- `app/lib/models/user_model.dart` — UserModel with isAdmin/isSeller/isManager
- `app/lib/providers/user_provider.dart` — allUsersProvider, UserNotifier
- `app/lib/providers/auth_provider.dart` — authUserProvider (StreamProvider)
- `app/lib/screens/settings_screen.dart` — user list + edit dialog

## Role Normalization Rules
1. Always read roles trimmed+lowercased: `role.trim().toLowerCase()`
2. `isAdmin` = role == 'admin' OR role == 'manager' (legacy)
3. `isSeller` = role == 'seller'
4. Never write non-canonical role values — write only 'admin' or 'seller'

## User CRUD Pattern
- Create: Secondary `FirebaseApp` approach — admin signs in to a throwaway secondary app instance to call `createUserWithEmailAndPassword`, writes Firestore user doc, then deletes the secondary app. No Cloud Functions needed.
- Update: `UserManagementNotifier.updateUser()` → batch write to Firestore only
- Delete: `UserManagementNotifier.deleteUser()` → soft-delete: set `active = false`, clear route assignments. Auth account is orphaned but rules deny all access when `active != true`.
- Password reset: `UserManagementNotifier.sendPasswordResetForSeller(email:)` → sends Firebase Auth password reset email. Admin cannot directly set passwords.

## Email Field Rules
- Email is immutable after creation → `enabled: false` in edit dialog
- Edit user dialog: name, role, route assignment, and "Send Password Reset Email" button
- Only sellers have assignedRouteId; admins do not

## Firestore Security
- Admin: full CRUD on `users` collection
- Seller: read-only own document + limited self-update (display_name, updated_at, last_active)
- Bootstrap admin allowed on empty collection

## Common Pitfalls
- Do NOT use Cloud Functions for user management — zero-cost Firebase tier (Firestore + Auth only)
- Secondary FirebaseApp must be deleted after user creation to avoid resource leaks
- Role mismatch between Firestore 'admin' and old 'manager' → rules and model both accept both
- `active != true` users get permission-denied on all protected reads

## 3-Step VERIFY_EMAIL / Custom-Token Flow

When a user's ID token is rejected mid-session (INVALID_ID_TOKEN):

```
Step 1: getIdToken(forceRefresh: true)
         ↓ success → continue
         ↓ fail
Step 2: signInWithCustomToken(token from secondary FirebaseApp)
         ↓ success → continue
         ↓ fail
Step 3: authNotifier.signOut() → redirect to /login
```

**Secondary FirebaseApp pattern for user creation:**
```dart
final secondaryApp = await Firebase.initializeApp(
  name: 'AdminUserCreate_${DateTime.now().millisecondsSinceEpoch}',
  options: Firebase.app().options,
);
final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
await secondaryAuth.createUserWithEmailAndPassword(
  email: email, password: password);
// write Firestore doc
await secondaryApp.delete(); // MUST delete to avoid resource leak
```

## Password Reset Direct Path

```dart
// In UserManagementNotifier:
Future<void> sendPasswordResetForSeller(String email) async {
  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
}
```

- Admin cannot read or set passwords directly — Firebase handles hashing.
- UI: "Send Password Reset Email" button in edit user dialog.
- Email field in edit dialog: always `enabled: false` (immutable after creation).

## Service Account Credentials Cache Pattern

When CI/CD needs Firestore Admin SDK access:
```yaml
- uses: google-github-actions/auth@v2
  with:
    credentials_json: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
- uses: google-github-actions/setup-gcloud@v2
```
Never commit service account JSON files. Cache the token via the GitHub Actions
`auth` action — credentials survive the full job without additional fetches.
