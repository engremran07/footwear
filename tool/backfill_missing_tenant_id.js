#!/usr/bin/env node

/**
 * P0-4: Backfill missing tenant_id fields across all tenant-owned collections.
 * 
 * This script identifies documents that are missing tenant_id and adds it based on:
 * - For collections scoped to a specific user (seller_inventory, etc.): derive from user doc
 * - For standalone collections (routes, products, etc.): use 'default' tenant
 * - Idempotent: safe to run multiple times (checks before updating)
 * 
 * Usage:
 *   node tool/backfill_missing_tenant_id.js [--dry-run] [--tenant=TENANT_ID] [--collection=NAME]
 * 
 * Examples:
 *   node tool/backfill_missing_tenant_id.js --dry-run                # Preview all changes
 *   node tool/backfill_missing_tenant_id.js --tenant=default        # Backfill only 'default' tenant
 *   node tool/backfill_missing_tenant_id.js --collection=products   # Backfill only products collection
 */

const admin = require('firebase-admin');
const serviceAccount = require('../google-play-service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://footwear-erp.firebaseio.com',
});

const db = admin.firestore();

// Parse command-line arguments
const args = process.argv.slice(2);
const isDryRun = args.includes('--dry-run');
const tenantFilter = args.find(a => a.startsWith('--tenant='))?.split('=')[1];
const collectionFilter = args.find(a => a.startsWith('--collection='))?.split('=')[1];

const DEFAULT_TENANT_ID = 'default';

/**
 * Collections that require tenant_id field.
 * - key: collection name
 * - value: whether to derive tenant_id from user doc (true) or use DEFAULT_TENANT_ID (false)
 */
const TENANT_SCOPED_COLLECTIONS = {
  products: false,                    // Use DEFAULT_TENANT_ID
  product_variants: false,            // Use DEFAULT_TENANT_ID
  routes: false,                      // Use DEFAULT_TENANT_ID
  customers: false,                   // Use DEFAULT_TENANT_ID (shops collection)
  transactions: false,                // Use DEFAULT_TENANT_ID
  invoices: false,                    // Use DEFAULT_TENANT_ID
  seller_inventory: true,             // Derive from seller user doc
  inventory_transactions: true,       // Derive from seller user doc
  notifications: false,               // Use DEFAULT_TENANT_ID
};

let totalProcessed = 0;
let totalBackfilled = 0;
const backfillLog = {};

/**
 * Derives tenant_id from a user document.
 * Returns tenant_id if set, otherwise DEFAULT_TENANT_ID.
 */
async function getTenantIdForUser(userId) {
  try {
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const data = userDoc.data();
      return data.tenant_id || DEFAULT_TENANT_ID;
    }
  } catch (err) {
    console.error(`Failed to fetch user doc ${userId}:`, err.message);
  }
  return DEFAULT_TENANT_ID;
}

/**
 * Backfills tenant_id for a single document.
 * Returns true if updated, false if already has tenant_id.
 */
async function backfillDocument(docRef, tenantId) {
  const doc = await docRef.get();
  if (!doc.exists) {
    return false; // Document doesn't exist
  }

  const data = doc.data();
  if (data.tenant_id) {
    return false; // Already has tenant_id
  }

  if (!isDryRun) {
    await docRef.update({
      tenant_id: tenantId,
      updated_at: admin.firestore.Timestamp.now(),
    });
  }

  return true;
}

/**
 * Process all documents in a collection to backfill tenant_id.
 */
async function processCollection(collectionName) {
  if (collectionFilter && collectionName !== collectionFilter) {
    return;
  }

  const deriveFromUser = TENANT_SCOPED_COLLECTIONS[collectionName];
  console.log(`\nProcessing ${collectionName}...`);

  const collectionRef = db.collection(collectionName);
  let backfilled = 0;
  let processed = 0;
  let lastDoc = null;
  let hasMore = true;

  while (hasMore) {
    try {
      let query = collectionRef.limit(100);
      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      hasMore = snapshot.docs.length === 100;

      for (const docSnapshot of snapshot.docs) {
        processed++;
        totalProcessed++;

        let tenantId = DEFAULT_TENANT_ID;

        // Derive tenant_id from user doc if applicable
        if (deriveFromUser) {
          const data = docSnapshot.data();
          // For seller_inventory and inventory_transactions: use seller_id
          // For per-user collections: derive from the user's tenant_id
          const userId = data.seller_id || data.created_by;
          if (userId) {
            tenantId = await getTenantIdForUser(userId);
          }
        }

        // Apply tenant filter if specified
        if (tenantFilter && tenantId !== tenantFilter) {
          continue;
        }

        const wasBackfilled = await backfillDocument(docSnapshot.ref, tenantId);
        if (wasBackfilled) {
          backfilled++;
          totalBackfilled++;
        }

        if ((processed % 50) === 0) {
          console.log(`  [${collectionName}] Processed ${processed} docs, backfilled ${backfilled}`);
        }
      }

      if (snapshot.docs.length > 0) {
        lastDoc = snapshot.docs[snapshot.docs.length - 1];
      }
    } catch (err) {
      console.error(`Error processing ${collectionName}:`, err.message);
      break;
    }
  }

  backfillLog[collectionName] = { processed, backfilled };
  console.log(`  [${collectionName}] Final: ${processed} docs processed, ${backfilled} backfilled`);
}

/**
 * Main backfill process.
 */
async function backfill() {
  try {
    console.log('╔════════════════════════════════════════╗');
    console.log('║ Tenant ID Backfill Utility             ║');
    console.log(`║ Mode: ${isDryRun ? 'DRY-RUN (no changes)' : 'LIVE (will update)   '} ║`);
    if (tenantFilter) console.log(`║ Tenant filter: ${tenantFilter.padEnd(27)} ║`);
    if (collectionFilter) console.log(`║ Collection filter: ${collectionFilter.padEnd(19)} ║`);
    console.log('╚════════════════════════════════════════╝');

    // Process all tenant-scoped collections
    for (const [collectionName] of Object.entries(TENANT_SCOPED_COLLECTIONS)) {
      await processCollection(collectionName);
    }

    console.log('\n╔════════════════════════════════════════╗');
    console.log('║ Backfill Summary                       ║');
    console.log('╚════════════════════════════════════════╝');
    console.log(`Total docs processed: ${totalProcessed}`);
    console.log(`Total docs backfilled: ${totalBackfilled}`);
    console.log('\nPer-collection breakdown:');
    Object.entries(backfillLog).forEach(([name, stats]) => {
      const { processed, backfilled } = stats;
      console.log(`  ${name.padEnd(25)} ${processed.toString().padStart(6)} processed, ${backfilled.toString().padStart(6)} backfilled`);
    });

    if (isDryRun) {
      console.log('\n⚠️  DRY-RUN mode: No changes were committed.');
      console.log('Remove --dry-run flag to apply changes.');
    } else {
      console.log('\n✅ Backfill complete!');
    }
  } catch (err) {
    console.error('Fatal error:', err);
    process.exit(1);
  } finally {
    await admin.app().delete();
  }
}

// Run backfill
backfill().catch(err => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
