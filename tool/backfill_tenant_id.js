#!/usr/bin/env node
'use strict';

const admin = require('firebase-admin');
const path = require('path');

const COLLECTIONS = [
  'users',
  'routes',
  'customers',
  'transactions',
  'invoices',
  'products',
  'product_variants',
  'seller_inventory',
  'inventory_transactions',
  'notifications',
];
const PAGE_SIZE = 500;
const BATCH_SIZE = 400;

function parseArgs() {
  const values = { apply: false };
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--apply') values.apply = true;
    else if (arg === '--project') values.project = argv[++i];
    else if (arg === '--tenant') values.tenant = argv[++i];
    else if (arg === '--key') values.key = argv[++i];
    else if (arg === '--collections') values.collections = argv[++i].split(',').map((v) => v.trim()).filter(Boolean);
    else if (arg === '--help') {
      console.log('Usage: node tool/backfill_tenant_id.js --project <id> --tenant <id> [--apply] [--key <json>] [--collections a,b]');
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!values.project || !values.tenant) {
    throw new Error('--project and --tenant are required');
  }
  if (values.tenant === '__global__' || values.tenant === 'global' || values.tenant.startsWith('__')) {
    throw new Error('Reserved tenant ids are not valid backfill targets');
  }
  return values;
}

function hasTenant(data) {
  const value = data.tenant_id;
  return typeof value === 'string' && value.trim().length > 0;
}

function credentialFor(options) {
  if (options.key) {
    return admin.credential.cert(require(path.resolve(options.key)));
  }
  return admin.credential.applicationDefault();
}

async function main() {
  const options = parseArgs();
  admin.initializeApp({
    credential: credentialFor(options),
    projectId: options.project,
  });
  const db = admin.firestore();
  const targetCollections = options.collections || COLLECTIONS;
  const runId = new Date().toISOString();
  const tenant = await db.collection('tenants').doc(options.tenant).get();
  if (!tenant.exists) throw new Error(`tenants/${options.tenant} does not exist`);

  console.log(`project=${options.project} tenant=${options.tenant} mode=${options.apply ? 'APPLY' : 'DRY-RUN'} run=${runId}`);
  if (options.apply) {
    console.log('APPLY mode starts in 5 seconds. Stop now if a backup has not been taken.');
    await new Promise((resolve) => setTimeout(resolve, 5000));
  }

  for (const collectionName of targetCollections) {
    let scanned = 0;
    let missing = 0;
    let updated = 0;
    let last = null;
    let batch = db.batch();
    let pending = 0;

    while (true) {
      let query = db.collection(collectionName)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(PAGE_SIZE);
      if (last) query = query.startAfter(last);
      const snapshot = await query.get();
      if (snapshot.empty) break;

      for (const doc of snapshot.docs) {
        scanned += 1;
        const data = doc.data();
        if (hasTenant(data)) continue;
        if (collectionName === 'users' && String(data.role || '').trim().toLowerCase() === 'super_admin') continue;
        missing += 1;
        if (options.apply) {
          batch.update(doc.ref, {
            tenant_id: options.tenant,
            tenant_backfill_run: runId,
            updated_at: admin.firestore.Timestamp.now(),
          });
          pending += 1;
          if (pending >= BATCH_SIZE) {
            await batch.commit();
            updated += pending;
            batch = db.batch();
            pending = 0;
          }
        }
      }

      last = snapshot.docs[snapshot.docs.length - 1];
      if (snapshot.size < PAGE_SIZE) break;
    }

    if (options.apply && pending > 0) {
      await batch.commit();
      updated += pending;
    }
    console.log(`${collectionName}: scanned=${scanned} missing=${missing} updated=${updated}`);
  }

  console.log(options.apply ? 'Backfill complete.' : 'Dry run only; no documents were written.');
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
