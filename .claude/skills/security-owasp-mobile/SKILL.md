---
name: security-owasp-mobile
description: "Use when: reviewing ShoesERP mobile security, Firebase Authentication, Firestore Rules, tenant isolation, secrets, input validation, backups, or OWASP MASVS/mobile risks."
---

# Skill: ShoesERP Mobile and Firebase Security Review

## Review Standard

Use current OWASP and Firebase documentation, then verify every claim against
the checked-out source, tests, and configuration. This checklist is an audit
guide, not a certification or a claim that ShoesERP is OWASP compliant. Record
evidence, severity, confidence, scope, and unresolved limitations.

## Authentication and Authorization

- Firebase Authentication is the app's sign-in mechanism. Firebase SDK token
  refresh and persistence are distinct from app-managed sessions.
- The current source has no app-managed device registration, pairing approval,
  session slots, renewal loop, or custom session gate. Do not recommend restoring
  these controls unless the product owner explicitly changes the requirement.
- Verify active Firestore profile and role checks, concrete tenant assignment,
  seller route scope, and selected-workspace support context for platform
  super-admin business access.
- Firestore Rules are the server-side data authorization boundary. Router
  visibility and provider guards are defense in depth, not substitutes.
- Client-side session tracking cannot bind ordinary Firestore requests to a
  custom session ID. App Check is an app/device attestation signal, not a
  replacement for Rules or authorization.
- Client code must not create/promote super-admins, administer arbitrary users'
  Auth credentials, or contain service-account credentials. Use owner-controlled
  Firebase Auth flows or an explicitly authorized trusted backend.
- Never report MFA, token revocation, App Check enforcement, or a session
  timeout as present without verifying current source and Firebase project
  configuration.

## Firestore Rules and Tenant Boundaries

- Confirm deny-by-default behavior and role normalization from the actual
  `firestore.rules` and `UserModel`.
- Check every business collection for tenant ownership and role-specific
  authorization. An active user profile does not imply that the user's tenant
  is active.
- Verify that inactive workspaces deny ordinary business access while allowing
  only the intentionally supported selected-super-admin restoration flow.
- Check `get`, `exists`, and `getAfter` access-call counts and Rules expression
  complexity for representative atomic batches. The Firestore Rules Emulator
  enforces the expression evaluation limit; preserve valid seller and admin
  invoice, ledger, shop-balance, and stock batches.
- A shop must not be created with a fabricated opening balance or cached
  transaction fields.
- Standalone transaction rows must be linked to their same-batch shop/balance
  update. Invoice flows may contain multiple ledger rows and must be validated
  against the invoice's aggregate delta; do not assume one row equals one
  balance change.
- Validate adversarial cases and legitimate CRUD in
  `tests/firestore-rules/rules.test.js`. Run with:

  ```powershell
  Push-Location tests/firestore-rules
  firebase emulators:exec --only firestore "npm test"
  Pop-Location
  ```

Rules tests do not prove production deployment state. Do not deploy rules or
indexes without explicit authorization.

## Data Integrity and Privacy

- Follow `shop.balance` as the sole financial source of truth. Invoice and
  transaction writes that affect it must be atomic and preserve ledger links.
- Preserve inventory audit records and exact invoice deductions for stock
  changes.
- Treat historical backups as sensitive. Verify tenant/route scoping,
  encryption, restore behavior, and pruning authority.
- Do not weaken established correction, deletion, or audit-history controls
  without tracing all provider and Rules paths and adding regression tests.
- Do not log credentials, access tokens, full PII, or sensitive document
  contents. Inspect error and analytics paths for accidental disclosure.
- Validate user-controlled input at the provider boundary; UI-only validation
  is insufficient for security-critical writes.

## Mobile and Release Surfaces

- Inspect Android permissions, exported components, deep links, release
  debuggability, signing configuration, and ProGuard/R8 behavior in the actual
  manifest and Gradle files.
- Verify secrets are not committed or passed through client build defines.
  Public Firebase client configuration is not equivalent to a service-account
  credential; access still depends on Rules and API restrictions.
- Confirm external product image URLs are restricted to HTTPS where enforced.
- Do not claim data is encrypted by application-level cryptography merely
  because Firebase encrypts service data at rest or TLS protects transport.
- Distinguish local builds, emulator tests, deployed Hosting, deployed Rules,
  and APK installation in every security report.

## Required Report Format

For each finding, include:

| Field | Required evidence |
|---|---|
| Severity | Critical, high, medium, or low with rationale |
| Location | File and exact line(s) |
| Attack preconditions | Required role, tenant, and request state |
| Impact | Concrete confidentiality, integrity, or availability effect |
| Reproduction | Safe emulator/test evidence; no production exploitation |
| Remediation | Minimal source change and regression test |
| Confidence | 1–10, reflecting evidence quality |
| Status | Verified fixed, open, or blocked; identify deployment status |

Do not test against production accounts or mutate live data unless the user
explicitly authorizes that target and action.
