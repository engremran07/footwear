---
name: user-management
description: "Use when: managing Firebase Auth-linked profiles, tenant roles, workspace membership, route assignment, password recovery, or user-access regressions."
---

# Skill: User Management

## Scope and Sources of Truth

User administration changes both Firebase Auth and tenant-scoped Firestore
profiles. Inspect the current implementation before editing:

- `app/lib/models/user_model.dart`
- `app/lib/core/utils/role_names.dart`
- `app/lib/core/utils/permission_policy.dart`
- `app/lib/providers/user_provider.dart`
- `app/lib/providers/auth_provider.dart`
- `app/lib/screens/users_list_screen.dart`
- `firestore.rules` and `tests/firestore-rules/rules.test.js`

`RoleCapabilities` and `PermissionPolicy` centralize app-side capabilities and
context checks. They do not replace Firestore Rules: Rules remain the
authorization boundary. Keep both layers aligned through positive and negative
emulator tests.

For cross-feature workspace isolation, invoice-operation parity, and
15-workspace regression guidance, use
`.claude/skills/multi-tenant-saas/SKILL.md` alongside this user-lifecycle
workflow.

## Canonical Roles and Tenant Scope

Read aliases through `canonicalRoleName()`; new profile writes use canonical
values only: `admin`, `tenant_admin`, `super_admin`, `supervisor`, and `seller`.
Legacy `manager` parses as `admin`.

| Role | User-management scope |
| --- | --- |
| `admin` / legacy `manager` | May manage eligible seller profiles in the same workspace only |
| `tenant_admin` | May manage eligible seller and supervisor profiles in the same workspace; cannot promote peers to admin/platform roles, change the permanent owner role, or deactivate peer administrators |
| `super_admin` | May manage workspace-scoped roles only while the selected workspace support context is valid, audited, and unexpired |
| `supervisor` | Operational access only; no user administration |
| `seller` | Own profile only, except no arbitrary-user account administration |

Every ordinary business profile must be active and have a concrete `tenant_id`.
Do not treat `__global__` or a missing tenant as a write fallback. Super-admin
business administration requires an explicit selected workspace and valid
support reason; metadata-only platform access remains separate.

## User CRUD and Membership Integrity

- Create profiles through `UserManagementNotifier.createUser()`. It uses a
  disposable secondary Firebase app for Auth account creation, then writes the
  profile, tenant seat counter, and route assignments transactionally. If the
  Firestore transaction fails, remove the newly created Auth account; report a
  cleanup failure explicitly.
- Validate the current actor from a fresh server profile, the concrete
  workspace, the target role, and every route ID before writing.
- Keep tenant seat changes atomic with profile activation/deactivation.
- `updateUser()` accepts only the provider's editable-field allowlist. Do not
  let UI visibility substitute for provider and Rules guards.
- Deactivation is a soft status change. Route assignment changes and route
  membership arrays must remain consistent in the same authorized flow.
- Do not create or promote platform super-admins from client code. Arbitrary
  Auth administration belongs in a trusted backend, which is not part of this
  Spark-tier client architecture.

## Credentials and Recovery

- Profile email is read-only in administrator editing. An account owner may
  request an email change through Firebase Auth's owner-controlled
  reauthentication and verification flow.
- Administrators request a reset by target user ID. Resolve the target profile
  server-side, validate same-workspace management scope and the allowed target
  role, then send to the stored email. Never accept an arbitrary email address
  from an administrator as the reset target.
- The account owner changes their own password after reauthentication.
  Preserve password input exactly; do not trim it before validation,
  reauthentication, creation, or update. Enforce the minimum length against the
  exact entered value.
- Firebase Auth owns credential and token lifecycle. Do not add custom tokens,
  client-managed session slots, device registration, pairing, or sign-in policy
  fields as an authorization boundary.
- Never store password material, service-account credentials, or Auth secrets
  in Firestore, backups, logs, source, or build defines.

## Verification

For any user-access change:

1. Test the screen's initial auth/profile loading state and the intended
   actionable error state.
2. Test the allowed actor/target-role/workspace combination and denied
   cross-workspace, peer-admin, owner, inactive-profile, and expired
   super-admin context cases as applicable.
3. Replay the complete client transaction or batch in the Firestore Emulator;
   include a denied attack and a valid operation.
4. Run focused Flutter tests, `flutter analyze lib --no-pub`, and
   `dart analyze test/` when tests change.
5. Keep exact command output and distinguish local emulator evidence from
   production Rules deployment.
