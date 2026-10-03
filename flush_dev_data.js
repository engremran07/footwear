/**
 * flush_dev_data.js
 *
 * DEV/TESTING ONLY — wipes financial data for one selected tenant.
 *
 * Usage:
 *   FIREBASE_PROJECT_ID=<dev-project> ALLOWED_DEV_FIREBASE_PROJECT_ID=<dev-project>
 *   FIREBASE_TENANT_ID=<tenant> node flush_dev_data.js
 *   Add --apply to commit; confirm by typing project:tenant.
 *
 * Requires firebase-admin with Application Default Credentials (ADC).
 * Run from the repo root where google-services.json / ADC is configured:
 *   set GOOGLE_APPLICATION_CREDENTIALS=path\to\service-account.json
 *   node flush_dev_data.js --apply
 */

const admin = require('firebase-admin');

function argValue(name) {
  const prefix = `--${name}=`;
  const arg = process.argv.find((value) => value.startsWith(prefix));
  return arg ? arg.slice(prefix.length) : null;
}

const PROJECT_ID = argValue('project') || process.env.FIREBASE_PROJECT_ID || '';
const TENANT_ID = argValue('tenant') || process.env.FIREBASE_TENANT_ID || '';
const ALLOWED_DEV_PROJECT_ID = process.env.ALLOWED_DEV_FIREBASE_PROJECT_ID || '';
const PRODUCTION_PROJECT_ID = 'shoeserp-clean-20260327';
const DRY_RUN = !process.argv.includes('--apply');
const BATCH_SIZE = 400;

let db;

async function validateTarget() {
  if (!PROJECT_ID || !TENANT_ID || !ALLOWED_DEV_PROJECT_ID) {
    throw new Error(
      'Set FIREBASE_PROJECT_ID, FIREBASE_TENANT_ID, and ALLOWED_DEV_FIREBASE_PROJECT_ID before running.',
    );
  }
  if (PROJECT_ID === PRODUCTION_PROJECT_ID || PROJECT_ID !== ALLOWED_DEV_PROJECT_ID) {
    throw new Error('Refusing flush: project is not the explicitly allowlisted development project.');
  }
  if (TENANT_ID === '__global__' || TENANT_ID === 'global') {
    throw new Error('Refusing flush: a concrete tenant ID is required.');
  }
  if (!DRY_RUN) {
    const expected = `${PROJECT_ID}:${TENANT_ID}`;
    const answer = await new Promise((resolve) => {
      const readline = require('readline').createInterface({
        input: process.stdin,
        output: process.stdout,
      });
      readline.question(`Type ${expected} to confirm destructive flush: `, (value) => {
        readline.close();
        resolve(value.trim());
      });
    });
    if (answer !== expected) throw new Error('Target confirmation failed.');
  }
  admin.initializeApp({ projectId: PROJECT_ID });
  db = admin.firestore();
}

async function deleteCollection(colName) {
  const snap = await db.collection(colName).where('tenant_id', '==', TENANT_ID).get();
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
  const ref = db.collection('settings').doc(TENANT_ID);
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

async function resetShopBalances() {
  const snap = await db.collection('customers').where('tenant_id', '==', TENANT_ID).get();
  console.log(`  customers: ${snap.size} tenant-matched shops found`);
  if (DRY_RUN) return snap.size;
  for (let i = 0; i < snap.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    snap.docs.slice(i, i + BATCH_SIZE).forEach((doc) => {
      batch.update(doc.ref, { balance: 0, bad_debt: false, bad_debt_amount: 0 });
    });
    await batch.commit();
  }
  return snap.size;
}

async function main() {
  await validateTarget();
  console.log('\n════════════════════════════════════════════');
  console.log('  DEV DATA FLUSH');
  console.log(`  Project : ${PROJECT_ID}`);
  console.log(`  Tenant  : ${TENANT_ID}`);
  console.log(
    `  Mode    : ${DRY_RUN ? 'DRY RUN — no writes' : '⚠️  APPLY — deleting Firestore data'}`,
  );
  console.log('════════════════════════════════════════════\n');

  console.log('── Deleting collections ──');
  const txCount = await deleteCollection('transactions');
  const invCount = await deleteCollection('invoices');

  console.log('\n── Resetting counters ──');
  await resetInvoiceCounter();
  const shopCount = await resetShopBalances();

  console.log('\n── Summary ──');
  if (DRY_RUN) {
    console.log(`  Would delete: ${txCount} transactions, ${invCount} invoices`);
    console.log(`  Would reset : ${shopCount} shop balances and settings/${TENANT_ID}.last_invoice_number`);
    console.log('\n  Re-run with --apply to commit.\n');
  } else {
    console.log(`  Deleted : ${txCount} transactions, ${invCount} invoices`);
    console.log(`  Reset   : ${shopCount} shop balances and settings/${TENANT_ID}.last_invoice_number`);
    console.log('\n  ✓ Dev flush complete. Firestore is clean.\n');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error('Flush failed:', err);
  process.exit(1);
});
