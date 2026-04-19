#!/usr/bin/env node
/**
 * dev_restore.js — ShoesERP development backup restore tool
 *
 * Usage:
 *   node dev_restore.js <backup_file.json>
 *
 * Prerequisites:
 *   npm install firebase-admin
 *
 * Environment:
 *   GOOGLE_APPLICATION_CREDENTIALS — path to your Firebase service account JSON
 *   OR set serviceAccountPath below.
 *
 * CAUTION: This script will DELETE all existing documents in the selected
 * collections before restoring from the backup. Use only in dev environments.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const admin = require('firebase-admin');

// ─── Config ──────────────────────────────────────────────────────────────────
const BATCH_SIZE = 400; // Firestore batch limit (500 max, keep headroom)
const PAGE_SIZE = 500;  // Read page size

// ─── Init Firebase Admin ──────────────────────────────────────────────────────
if (!admin.apps.length) {
  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credPath) {
    console.error(
      'ERROR: Set GOOGLE_APPLICATION_CREDENTIALS env var to your service account JSON path.',
    );
    process.exit(1);
  }
  const serviceAccount = JSON.parse(fs.readFileSync(credPath, 'utf8'));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Recursively sort object keys — mirrors Dart SplayTreeMap sort for deterministic JSON. */
function sortedKeys(obj) {
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) return obj;
  const sorted = {};
  for (const k of Object.keys(obj).sort()) {
    sorted[k] = sortedKeys(obj[k]);
  }
  return sorted;
}

/** Compute SHA-256 of deterministically sorted JSON (mirrors Dart _checksum). */
function computeChecksum(data) {
  const sorted = sortedKeys(data);
  const json = JSON.stringify(sorted);
  return crypto.createHash('sha256').update(json, 'utf8').digest('hex');
}

/** Convert backup Timestamp sentinel back to Firestore Timestamp. */
function restoreTypes(value) {
  if (value === null || value === undefined) return value;
  if (typeof value === 'object' && !Array.isArray(value)) {
    if (value.__type === 'Timestamp' && value.s !== undefined && value.ns !== undefined) {
      return new admin.firestore.Timestamp(value.s, value.ns);
    }
    const restored = {};
    for (const k of Object.keys(value)) {
      restored[k] = restoreTypes(value[k]);
    }
    return restored;
  }
  if (Array.isArray(value)) {
    return value.map(restoreTypes);
  }
  return value;
}

/** Delete all documents in a collection (batched). */
async function deleteCollection(collectionName) {
  let count = 0;
  let last = null;
  while (true) {
    let q = db.collection(collectionName).limit(PAGE_SIZE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    count += snap.docs.length;
    last = snap.docs[snap.docs.length - 1];
    process.stdout.write(`  Deleted ${count} docs from ${collectionName}...\r`);
  }
  console.log(`  Deleted ${count} docs from ${collectionName}        `);
}

/** Write documents in batches. */
async function writeCollection(collectionName, docs) {
  let i = 0;
  const entries = Object.entries(docs);
  while (i < entries.length) {
    const batch = db.batch();
    const chunk = entries.slice(i, i + BATCH_SIZE);
    for (const [docId, rawData] of chunk) {
      const data = restoreTypes(rawData);
      batch.set(db.collection(collectionName).doc(docId), data);
    }
    await batch.commit();
    i += chunk.length;
    process.stdout.write(`  Wrote ${i}/${entries.length} docs to ${collectionName}...\r`);
  }
  console.log(`  Wrote ${entries.length} docs to ${collectionName}        `);
}

// ─── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node dev_restore.js <backup_file.json>');
    process.exit(1);
  }

  const filePath = path.resolve(args[0]);
  if (!fs.existsSync(filePath)) {
    console.error(`ERROR: File not found: ${filePath}`);
    process.exit(1);
  }

  console.log(`\nShoesERP Dev Restore Tool`);
  console.log(`=========================`);
  console.log(`Backup file: ${filePath}\n`);

  // ── Read and parse backup ─────────────────────────────────────────────────
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (e) {
    console.error(`ERROR: Invalid JSON — ${e.message}`);
    process.exit(1);
  }

  const { version, created_at, created_by, checksum, data } = raw;

  if (!version || !created_at || !checksum || !data) {
    console.error('ERROR: Backup file is missing required fields (version, created_at, checksum, data).');
    process.exit(1);
  }

  // ── Verify checksum ────────────────────────────────────────────────────────
  console.log(`Backup version : ${version}`);
  console.log(`Created at     : ${created_at}`);
  console.log(`Created by     : ${created_by ?? '(unknown)'}`);
  console.log(`\nVerifying SHA-256 checksum...`);

  const actualChecksum = computeChecksum(data);
  if (actualChecksum !== checksum) {
    console.error(`\nCHECKSUM MISMATCH!`);
    console.error(`  Expected : ${checksum}`);
    console.error(`  Actual   : ${actualChecksum}`);
    console.error(`\nBackup file may be corrupted or tampered with. Aborting.`);
    process.exit(1);
  }
  console.log(`Checksum OK ✓`);

  // ── Preview ────────────────────────────────────────────────────────────────
  const collections = Object.keys(data);
  console.log(`\nCollections to restore:`);
  let total = 0;
  for (const col of collections) {
    const count = Object.keys(data[col]).length;
    total += count;
    console.log(`  ${col.padEnd(30)} ${count} documents`);
  }
  console.log(`  ${'TOTAL'.padEnd(30)} ${total} documents`);

  // ── Confirm ────────────────────────────────────────────────────────────────
  console.log(`\n⚠️  WARNING: This will DELETE all existing documents in the`);
  console.log(`   collections listed above and replace them with the backup.`);
  console.log(`   This is IRREVERSIBLE. Use only in development environments.\n`);

  // Simple stdin confirmation
  const readline = require('readline');
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => {
    rl.question('Type "RESTORE" to confirm: ', resolve);
  });
  rl.close();

  if (answer.trim() !== 'RESTORE') {
    console.log('\nAborted.');
    process.exit(0);
  }

  // ── Restore ────────────────────────────────────────────────────────────────
  console.log('\nStarting restore...\n');
  for (const col of collections) {
    console.log(`[${col}]`);
    await deleteCollection(col);
    await writeCollection(col, data[col]);
  }

  // ── Reset settings ─────────────────────────────────────────────────────────
  console.log('\nResetting last_invoice_number in settings/global...');
  try {
    await db.collection('settings').doc('global').set(
      { last_invoice_number: 0 },
      { merge: true },
    );
    console.log('  Done.');
  } catch (e) {
    console.warn(`  WARNING: Could not reset settings/global — ${e.message}`);
  }

  console.log(`\n✅ Restore complete! ${total} documents restored across ${collections.length} collections.`);
  process.exit(0);
}

main().catch((e) => {
  console.error('\nUnhandled error:', e);
  process.exit(1);
});
