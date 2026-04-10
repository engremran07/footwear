/**
 * flush_dev_data.js
 *
 * DEV/TESTING ONLY — wipes `transactions` and `invoices` collections
 * and resets the invoice counter in settings/global to 0.
 *
 * Usage:
 *   node flush_dev_data.js          ← dry run (shows counts, no writes)
 *   node flush_dev_data.js --apply  ← commits the flush
 *
 * Requires firebase-admin with Application Default Credentials (ADC).
 * Run from the repo root where google-services.json / ADC is configured:
 *   set GOOGLE_APPLICATION_CREDENTIALS=path\to\service-account.json
 *   node flush_dev_data.js --apply
 */

const admin = require('./functions/node_modules/firebase-admin');

const PROJECT_ID = 'shoeserp-clean-20260327';
const DRY_RUN = !process.argv.includes('--apply');
const BATCH_SIZE = 400;

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function deleteCollection(colName) {
  const snap = await db.collection(colName).get();
  console.log(`  ${colName}: ${snap.size} docs found`);
  if (snap.size === 0 || DRY_RUN) return snap.size;

  for (let i = 0; i < snap.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    snap.docs.slice(i, i + BATCH_SIZE).forEach((d) => batch.delete(d.ref));
    await batch.commit();
    console.log(
      `  ${colName}: deleted docs ${i + 1}–${Math.min(i + BATCH_SIZE, snap.docs.length)}`,
    );
  }
  return snap.size;
}

async function resetInvoiceCounter() {
  const ref = db.collection('settings').doc('global');
  const snap = await ref.get();
  const current = snap.exists ? (snap.data().last_invoice_number ?? 'not set') : 'doc missing';
  console.log(`  settings/global.last_invoice_number: ${current}`);
  if (DRY_RUN) return;
  if (snap.exists) {
    await ref.update({ last_invoice_number: 0 });
  } else {
    await ref.set({ last_invoice_number: 0 }, { merge: true });
  }
  console.log('  settings/global.last_invoice_number → reset to 0');
}

async function main() {
  console.log('\n════════════════════════════════════════════');
  console.log('  DEV DATA FLUSH');
  console.log(`  Project : ${PROJECT_ID}`);
  console.log(
    `  Mode    : ${DRY_RUN ? 'DRY RUN — no writes' : '⚠️  APPLY — deleting Firestore data'}`,
  );
  console.log('════════════════════════════════════════════\n');

  console.log('── Deleting collections ──');
  const txCount = await deleteCollection('transactions');
  const invCount = await deleteCollection('invoices');

  console.log('\n── Resetting counters ──');
  await resetInvoiceCounter();

  console.log('\n── Summary ──');
  if (DRY_RUN) {
    console.log(`  Would delete: ${txCount} transactions, ${invCount} invoices`);
    console.log('  Would reset : last_invoice_number → 0');
    console.log('\n  Re-run with --apply to commit.\n');
  } else {
    console.log(`  Deleted : ${txCount} transactions, ${invCount} invoices`);
    console.log('  Reset   : last_invoice_number → 0');
    console.log('\n  ✓ Dev flush complete. Firestore is clean.\n');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error('Flush failed:', err);
  process.exit(1);
});
