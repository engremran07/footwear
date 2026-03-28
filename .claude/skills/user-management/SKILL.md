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
- Create: Firebase Admin via Cloud Function `manageUserAuth` (NOT createUserWithEmailAndPassword)
- Update: `UserNotifier.updateUser()` → batch write to Firestore only
- Deactivate: set `active = false` (never hard delete)
- Password reset: `UserNotifier.sendPasswordResetEmail(email)`

## Email Field Rules
- Email is immutable after creation → `enabled: false` in edit dialog
- Only sellers have assignedRouteId; admins do not

## Firestore Security
- Admin: full CRUD on `users` collection
- Seller: read-only own document
- Bootstrap admin allowed on empty collection

## Common Pitfalls
- `FirebaseAuth.createUserWithEmailAndPassword` in app creates auth but NOT Firestore doc → use Cloud Function
- Role mismatch between Firestore 'admin' and old 'manager' → rules and model both accept both
- `active != true` users get permission-denied on all protected reads
