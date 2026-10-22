---
name: firebase-free-tier
description: "Use when: checking Firebase Spark-plan eligibility, Firestore quotas, Firebase Auth limits, read/write cost, or whether a proposed feature needs a paid plan."
---

# Skill: Firebase Plan and Quota Review

## Scope

Check Firebase product availability, billing-plan requirements, and usage against
current official documentation. Do not equate a repository design goal with an
enforced billing limit. Verify current plan and project usage before making
claims about production cost or quota headroom.

The application currently uses Firebase Authentication and Cloud Firestore. It
does not use Firebase Storage or Cloud Functions in the client architecture.
Company logos are stored as bounded base64 values in Firestore; product images
use external HTTPS URLs. Confirm manifests and source before repeating these
claims.

## Firestore Free Quota

As verified from the official Firestore quota documentation on 2026-10-22, the
free quota for one database per project includes:

| Resource | Free quota |
|---|---:|
| Stored data | 1 GiB |
| Document reads | 50,000 per day |
| Document writes | 20,000 per day |
| Document deletes | 20,000 per day |
| Outbound data transfer | 10 GiB per month |

These values and free-tier eligibility can change. Consult the linked official
pricing and quota pages before planning capacity or promising zero cost. Other
Firebase products have separate limits and may require billing, even when
Firestore remains within its free quota.

Firebase Authentication does not have a generic “10,000 operations/month”
limit. Limits vary by operation and sign-in provider. Check the current
Authentication limits and pricing pages for the exact operation in scope.

## Project Architecture Checks

- Do not add `firebase_storage` or Storage APIs; the current app contract excludes
  Firebase Storage.
- Do not add Cloud Functions or other paid-plan dependencies without explicit
  product and billing review.
- Never embed service-account credentials or privileged credentials in client
  code, Firestore, backups, or build defines.
- The Firebase client configuration is not a service-account secret. Verify API
  key restrictions and Firebase Security Rules separately; obscuring a client
  key is not an authorization boundary.
- `docSizeOk()` in `firestore.rules` limits the number of document fields
  (`request.resource.data.size() < 100`). It does not measure bytes or enforce
  a 50 KB cap.
- Workspace logo size limits are application validation, not the meaning of
  `docSizeOk()`. Confirm the actual provider and Rules checks before stating
  their exact bounds.
- Firestore Rules do not filter query results. A query must be authorized for
  every possible result document; test the actual query shape and index.

## Read and Write Cost Review

For each proposed listener or query:

1. Identify its source collection, filters, order, limit, refresh behavior, and
   consuming UI.
2. Prefer an existing scoped stream when it meets the feature's freshness and
   completeness requirements. Avoid redundant listeners.
3. Use a visible limit for UI windows when the screen communicates truncation.
   Full exports and backups must cursor-page until the result is exhausted.
4. Account for document reads caused by listener snapshots, query results,
   transaction retries, and Firestore Rules document-access calls. Repeated
   Rules lookups may be cached during evaluation; do not assume every call
   creates a distinct billable read.
5. Avoid invoking queries repeatedly in rebuilds or loops. Derive display
   metrics from already-loaded data only when that preserves correctness.
6. Keep multi-document financial changes atomic. Never trade balance/ledger
   integrity for fewer writes.

`withinWriteRate()` is a repository-specific write guard, not a Firebase free
quota. Apply it only where the rules and runtime flow require it; do not add it
to high-frequency or atomic financial paths without testing their valid batches.

`collectionGroup` is a supported Firestore query feature, not categorically
more expensive or forbidden. Review its result scope, indexes, Rules query
authorization, and measured cost before using or rejecting it.

## Verification Procedure

1. Inspect `app/pubspec.yaml`, the relevant service/provider code,
   `firebase.json`, `firestore.rules`, and current workflow definitions.
2. Verify claimed billing/limit details against official Firebase pricing,
   quotas, and Authentication documentation.
3. Run the relevant emulator or unit tests; do not deploy as a substitute for
   local validation.
4. Use Firebase Console usage metrics only when project access and explicit
   authorization are available. Do not infer live usage from source code.
5. Report uncertainty, source date, and whether the conclusion describes code,
   emulator evidence, or live project configuration.

## Official References

- [Firebase pricing plans](https://firebase.google.com/pricing)
- [Cloud Firestore quotas and free quota](https://firebase.google.com/docs/firestore/quotas)
- [Firebase Authentication limits](https://firebase.google.com/docs/auth/limits)
- [Cloud Firestore pricing](https://firebase.google.com/docs/firestore/pricing)
