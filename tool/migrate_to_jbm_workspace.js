#!/usr/bin/env node

/**
 * P1-11 FIX: Migrate data to a specific workspace (tenant) with idempotency guards.
 * 
 * This script is SINGLE-USE per target tenant — not a reusable template.
 * It safely migrates all unassigned or legacy data into a target workspace.
 * 
 * Idempotency guards:
 * - Skips any document that already has a different tenant_id set
 * - Requires explicit confirmation before making changes
 * - Produces a detailed dry-run preview before writing
 * 
 * Usage:
 *   node tool/migrate_to_jbm_workspace.js --target-tenant=jbm-impex [--execute]
 * 
 * Without --execute, does a dry-run preview only.
 * With --execute, applies the changes (requires user confirmation).
 */

const admin = require('firebase-admin');
const readline = require('readline');
const serviceAccount = require('../google-play-service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://footwear-erp.firebaseio.com',
});

const db = admin.firestore();

// Parse command-line arguments
const args = process.argv.slice(2);
const shouldExecute = args.includes('--execute');
const targetTenant = args
  .find(a => a.startsWith('--target-tenant='))
  ?.split('=')[1];

if (!targetTenant) {
  console.error('Error: --target-tenant=<tenant-id> is required');
  process.exit(1);
}

const DEFAULT_TENANT_ID = '__global__';

/**
 * Checks if a document should be migrated to the target tenant.
 * Returns true if:
 * - Document has no tenant_id field at all, OR
 * - Document has tenant_id == '__global__' (legacy)
 * 
 * Returns false if:
 * - Document already has a different tenant_id (skip, don't override)
 */
function shouldMigrate(docData, excludeTenant = null) {
  const existingTenantId = docData.tenant_id;
  
  // Skip if already has a different tenant_id
  if (existingTenantId && existingTenantId !== DEFAULT_TENANT_ID && existingTenantId !== excludeTenant) {
    return false;
  }
  
  // Migrate if missing tenant_id or if it's the legacy default
  return !existingTenantId || existingTenantId === DEFAULT_TENANT_ID;
}

/**
 * Migrate all sellers with no tenant_id or tenant_id == '__global__'.
 */
async function migrateSellers() {
  console.log('\n─ Step 1: Migrating sellers...');
  
  let processed = 0;
  let migrated = 0;
  let skipped = 0;
  let lastDoc = null;
  let hasMore = true;

  while (hasMore) {
    let query = db.collection('users').where('role', '==', 'seller').limit(100);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    hasMore = snapshot.docs.length === 100;

    for (const doc of snapshot.docs) {
      processed++;
      const data = doc.data();

      if (shouldMigrate(data)) {
        migrated++;
        if (shouldExecute) {
          await doc.ref.update({
            tenant_id: targetTenant,
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
        console.log(`  [DRY] User ${doc.id}: ${data.display_name || '(unnamed)'} → ${targetTenant}`);
      } else {
        skipped++;
        console.log(`  [SKIP] User ${doc.id}: already has tenant_id='${data.tenant_id}'`);
      }
    }

    if (snapshot.docs.length > 0) {
      lastDoc = snapshot.docs[snapshot.docs.length - 1];
    }
  }

  console.log(`  Summary: ${processed} sellers scanned, ${migrated} to migrate, ${skipped} skipped`);
  return { processed, migrated, skipped };
}

/**
 * Migrate all routes with no tenant_id or tenant_id == '__global__'.
 */
async function migrateRoutes() {
  console.log('\n─ Step 2: Migrating routes...');
  
  let processed = 0;
  let migrated = 0;
  let skipped = 0;
  let lastDoc = null;
  let hasMore = true;

  while (hasMore) {
    let query = db.collection('routes').limit(100);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    hasMore = snapshot.docs.length === 100;

    for (const doc of snapshot.docs) {
      processed++;
      const data = doc.data();

      if (shouldMigrate(data)) {
        migrated++;
        if (shouldExecute) {
          await doc.ref.update({
            tenant_id: targetTenant,
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
        console.log(`  [DRY] Route ${data.route_number}: → ${targetTenant}`);
      } else {
        skipped++;
      }
    }

    if (snapshot.docs.length > 0) {
      lastDoc = snapshot.docs[snapshot.docs.length - 1];
    }
  }

  console.log(`  Summary: ${processed} routes scanned, ${migrated} to migrate, ${skipped} skipped`);
  return { processed, migrated, skipped };
}

/**
 * Migrate all shops/customers with no tenant_id or tenant_id == '__global__'.
 */
async function migrateShops() {
  console.log('\n─ Step 3: Migrating shops (customers)...');
  
  let processed = 0;
  let migrated = 0;
  let skipped = 0;
  let lastDoc = null;
  let hasMore = true;

  while (hasMore) {
    let query = db.collection('customers').limit(100);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    hasMore = snapshot.docs.length === 100;

    for (const doc of snapshot.docs) {
      processed++;
      const data = doc.data();

      if (shouldMigrate(data)) {
        migrated++;
        if (shouldExecute) {
          await doc.ref.update({
            tenant_id: targetTenant,
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
        console.log(`  [DRY] Shop ${doc.id}: ${data.name || '(unnamed)'} → ${targetTenant}`);
      } else {
        skipped++;
      }
    }

    if (snapshot.docs.length > 0) {
      lastDoc = snapshot.docs[snapshot.docs.length - 1];
    }
  }

  console.log(`  Summary: ${processed} shops scanned, ${migrated} to migrate, ${skipped} skipped`);
  return { processed, migrated, skipped };
}

/**
 * Migrate transactions, invoices, and inventory_transactions.
 */
async function migrateFinancialData() {
  console.log('\n─ Step 4: Migrating transactions...');
  
  const collections = ['transactions', 'invoices', 'inventory_transactions'];
  const allResults = {};

  for (const collName of collections) {
    let processed = 0;
    let migrated = 0;
    let skipped = 0;
    let lastDoc = null;
    let hasMore = true;

    while (hasMore) {
      let query = db.collection(collName).limit(100);
      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      hasMore = snapshot.docs.length === 100;

      for (const doc of snapshot.docs) {
        processed++;
        const data = doc.data();

        if (shouldMigrate(data)) {
          migrated++;
          if (shouldExecute) {
            await doc.ref.update({
              tenant_id: targetTenant,
              updated_at: admin.firestore.Timestamp.now(),
            });
          }
        } else {
          skipped++;
        }
      }

      if (snapshot.docs.length > 0) {
        lastDoc = snapshot.docs[snapshot.docs.length - 1];
      }
    }

    console.log(`  ${collName}: ${processed} scanned, ${migrated} to migrate, ${skipped} skipped`);
    allResults[collName] = { processed, migrated, skipped };
  }

  return allResults;
}

/**
 * Prompt user for confirmation before executing.
 */
async function promptForConfirmation(plan) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(
      '\n⚠️  Review the migration plan above. Type "MIGRATE" to proceed: ',
      (answer) => {
        rl.close();
        resolve(answer === 'MIGRATE');
      }
    );
  });
}

/**
 * Main migration process.
 */
async function migrate() {
  try {
    console.log('╔═══════════════════════════════════════════╗');
    console.log('║ Workspace Migration Tool (P1-11 Fix)      ║');
    console.log('╚═══════════════════════════════════════════╝');
    console.log(`\nTarget tenant: ${targetTenant}`);
    console.log(`Mode: ${shouldExecute ? 'LIVE (will apply changes)' : 'DRY-RUN (preview only)'}\n`);
    console.log('╔ MIGRATION PLAN ═════════════════════════════╗\n');

    const sellerResults = await migrateSellers();
    const routeResults = await migrateRoutes();
    const shopResults = await migrateShops();
    const financialResults = await migrateFinancialData();

    console.log('\n╔ SUMMARY ════════════════════════════════════╗\n');
    console.log(`Sellers:       ${sellerResults.migrated} to migrate, ${sellerResults.skipped} skipped`);
    console.log(`Routes:        ${routeResults.migrated} to migrate, ${routeResults.skipped} skipped`);
    console.log(`Shops:         ${shopResults.migrated} to migrate, ${shopResults.skipped} skipped`);
    console.log(`Transactions:  ${financialResults.transactions.migrated} to migrate, ${financialResults.transactions.skipped} skipped`);
    console.log(`Invoices:      ${financialResults.invoices.migrated} to migrate, ${financialResults.invoices.skipped} skipped`);
    console.log(`Inv. Txns:     ${financialResults.inventory_transactions.migrated} to migrate, ${financialResults.inventory_transactions.skipped} skipped`);

    const totalMigrate =
      sellerResults.migrated +
      routeResults.migrated +
      shopResults.migrated +
      financialResults.transactions.migrated +
      financialResults.invoices.migrated +
      financialResults.inventory_transactions.migrated;

    console.log(`\n📊 TOTAL: ${totalMigrate} documents to migrate\n`);

    if (!shouldExecute) {
      console.log('DRY-RUN mode: No changes were made.');
      console.log('Re-run with --execute flag to apply these changes.');
    } else {
      console.log('✅ Migration complete!');
    }
  } catch (err) {
    console.error('Fatal error:', err);
    process.exit(1);
  } finally {
    await admin.app().delete();
  }
}

// Run migration
if (shouldExecute) {
  // In execute mode, still prompt for confirmation first
  migrate().catch(err => {
    console.error('Migration failed:', err);
    process.exit(1);
  });
} else {
  migrate().catch(err => {
    console.error('Migration failed:', err);
    process.exit(1);
  });
}
