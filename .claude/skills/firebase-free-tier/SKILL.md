---
name: firebase-free-tier
description: "Use when: ensuring all Firebase usage stays within Spark (free) plan limits, auditing for paid-only features, optimizing Firestore read/write counts, preventing quota exhaustion."
---

# Skill: Firebase Free-Tier Compliance (Spark Plan)

## Spark Plan Limits (as of 2026)
| Resource | Free Limit | Danger Zone |
|---|---|---|
| Firestore reads/day | 50,000 | >40,000 |
| Firestore writes/day | 20,000 | >16,000 |
| Firestore deletes/day | 20,000 | >16,000 |
| Firestore storage | 1 GB | >800 MB |
| Auth users | Unlimited | — |
| Auth operations | 10,000/month | — |
| Functions invocations | 0 (REMOVED from this app) | — |
| Storage | 0 (REMOVED from this app) | — |

## Zero-Cost Architecture Rules
1. **NO firebase_storage** — dependency must NOT be in pubspec.yaml
2. **NO Cloud Functions** — functions/index.js must only contain stub/no-op or be empty
3. **NO Blaze-only features**: no Extensions, no BigQuery exports, no Firestore backups
4. **Company logos**: base64 in Firestore settings doc, ≤50 KB cap enforced by docSizeOk()
5. **Product images**: external HTTP URLs only (URL field), never uploaded blobs

## Read Optimization Patterns
```dart
// GOOD: Stream (cached by Firestore SDK, only sends delta updates)
StreamProvider<List<T>>((ref) => FirebaseFirestore.instance
  .collection(col).snapshots().map(...))

// BAD: Future inside build() — re-reads entire collection each call
FutureProvider<List<T>>((ref) => FirebaseFirestore.instance
  .collection(col).get().then(...))

// GOOD: Limit queries to avoid full-collection scans
.limit(200)  // always set a reasonable limit

// GOOD: Dashboard derived from streams (zero extra reads)
Provider<AsyncValue<Stats>>((ref) => _computeFromStreams(ref));

// BAD: Aggregate queries (count/sum) in loops or on every rebuild
// Use computed values from already-loaded stream data instead
```

## Write Optimization Rules
- Batch related writes (e.g., invoice + balance update + stock deduction) in a single `WriteBatch`
- Avoid writes on every keystroke — debounce or write only on submit
- The `withinWriteRate()` rule in firestore.rules enforces 1s cooldown — respect it in UI

## Invoice Numbering (Atomic Counter)
The `settings/global.last_invoice_number` counter MUST use a Firestore Transaction (not batch) to prevent race conditions:
```dart
// CORRECT — atomic read-compute-write
await db.runTransaction((txn) async {
  final doc = await txn.get(settingsRef);
  final next = ((doc.data()?['last_invoice_number'] as int?) ?? 0) + 1;
  txn.update(settingsRef, {'last_invoice_number': next});
  return 'INV-${DateTime.now().year}-${next.toString().padLeft(4, '0')}';
});
// WRONG — read-then-update outside a transaction (race condition)
```

## Firestore Rules Free-Tier Guards
```javascript
// docSizeOk() — already in rules, prevents large doc abuse
function docSizeOk() {
  return request.resource.data.size() < 50000;
}

// withinWriteRate() — already in rules, 1s cooldown
function withinWriteRate() {
  return resource == null
    || !('updated_at' in resource.data)
    || request.time > resource.data.updated_at + duration.value(1, 's');
}
```

## Firestore Cost Killers to Avoid
- Real-time listeners on large collections without `.limit()` → add `.limit()`
- `get()` calls inside Firestore Rules (each = 1 extra read) → minimize `get()` in rules
- Multiple listeners on same collection in different providers → consolidate to one StreamProvider
- `collectionGroup` queries → avoid (expensive, hard to index)
- Dashboard aggregate queries → derive from already-loaded stream data (zero extra reads)

## Budget Alert Setup (Manual, via Console)
Since free tier has no budget alerts, monitor the Firebase Console daily:
- Firestore → Usage tab → check reads/writes
- Alert threshold: 80% of daily limit = 40K reads / 16K writes

## Free-Tier Monitoring Checklist
- [ ] No `firebase_storage` in pubspec.yaml
- [ ] No Cloud Functions in functions/ (or functions/ removed)
- [ ] All collections use `.limit()` in queries
- [ ] Dashboard stats computed from stream providers (not aggregate queries)
- [ ] Invoice numbering uses Firestore Transaction (not batch for counter)
- [ ] settings doc ≤50 KB (base64 logo compressed to 256×256, ≤50KB)
- [ ] No `collectionGroup` queries
- [ ] No `get()` calls in rules beyond what's already there
