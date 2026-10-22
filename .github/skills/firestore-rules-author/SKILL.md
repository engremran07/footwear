---
name: firestore-rules-author
description: "Use when: authoring or changing ShoesERP Firestore Security Rules, tenant authorization, shop/ledger/invoice atomicity, or Rules Emulator regressions."
---

# Skill: ShoesERP Firestore Rules Authoring

## Before Editing

1. Read `AGENTS.md`, `CLAUDE.md`, this instruction, the relevant Rules
   collection blocks, and matching tests in
   `tests/firestore-rules/rules.test.js`.
2. Trace the actual provider write batch and identify every document read,
   created, or updated. Preserve valid shop, route, invoice, ledger, and stock
   write flows.
3. Check `app/lib/models/user_model.dart`,
   `app/lib/core/constants/collections.dart`, `firestore.indexes.json`, and
   provider guards when a role, collection, or query is involved.
4. Add a regression that fails against the pre-fix Rules before changing the
   rule. Include an authorized valid path and a denied attack path.

## Runtime Authorization Contract

- Firebase Authentication is the sole sign-in mechanism. Do not add
  app-managed device registration, pairing, session slots, or renewal gates.
- Business documents require a concrete tenant and an active tenant. An active
  user profile alone does not authorize access to an inactive workspace.
- Preserve the selected-workspace and time-bounded support context for
  super-admin business access. Only the intended selected super-admin restore
  operation may reactivate an inactive tenant.
- Keep role aliases aligned: `manager` is admin-equivalent; `tenant_admin` is
  workspace-scoped; `super_admin` is platform-scoped, never a global business
  reader; sellers are route-scoped.
- Shop creation starts at zero balance and does not seed last-transaction
  metadata. Shop/route counters and ledger/shop balance updates must be in the
  same atomic write.
- Standalone `cash_in` and `cash_out` transactions require an exact linked shop
  balance update. Invoice flows may write multiple ledger rows against one
  aggregate balance delta; validate invoice references and the full batch
  rather than applying a one-row/one-delta assumption.
- Preserve invoice immutability/correction paths, seller stock deduction
  matching, inventory audit writes, and deny-by-default behavior.

## Rules Complexity and Testing

- Keep authorization clauses short-circuited: reject irrelevant roles before
  tenant document lookups.
- Minimize repeated `get`, `exists`, and `getAfter` work. Rules access-call and
  expression-evaluation limits apply to valid batches; do not accept a fix that
  makes legitimate invoice or seller inventory writes fail.
- Rules are not query filters. Test the actual query constraints and index
  requirements.
- Run the complete local suite from the repository root:

  ```powershell
  Push-Location tests/firestore-rules
  firebase emulators:exec --only firestore "npm test"
  Pop-Location
  ```

- Inspect exact pass/fail output and exercise the targeted valid and denied
  paths. Do not treat test-runner startup or a zero-test grep as a passing suite.
- Never deploy Rules/indexes or alter production data unless explicitly
  authorized by the user.

## Reporting

Report changed Rules and tests, why the change preserves existing valid flows,
the exact emulator result, and whether production deployment was authorized
and completed. A local emulator pass does not prove production state.

## References

- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Rules conditions and document access](https://firebase.google.com/docs/firestore/security/rules-conditions)
- [Rules unit testing](https://firebase.google.com/docs/rules/unit-tests)
