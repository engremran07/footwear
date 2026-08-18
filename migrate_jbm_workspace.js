#!/usr/bin/env node

/**
 * JBM Impex Workspace Data Migration Script
 * 
 * Purpose:
 *   Backfill tenant_id field for JBM Impex workspace migrated data
 *   Fixes data visibility issue where users can't see their data after migration
 * 
 * Problem:
 *   - Users migrated to JBM Impex workspace, but tenant_id field not set during migration
 *   - Providers filter by tenant_id; queries with null tenant_id return no results
 * 
 * Solution:
 *   Update all documents in collections: users, customers (shops), transactions, invoices
 *   Set tenant_id = 'jbm-impex' for all docs lacking tenant_id or where tenant_id is null/undefined
 * 
 * Usage:
 *   node migrate_jbm_workspace.js
 * 
 * Safety:
 *   - Reads from Firestore service account key (google-play-service-account.json)
 *   - Dry-run mode first (logs documents to update, doesn't actually write)
 *   - Then asks for confirmation before executing writes
 *   - Batches updates in groups of 500 (Firestore WriteBatch limit)
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const WORKSPACE_ID = 'jbm-impex';
const BATCH_SIZE = 500;

// ============================================================================
// FIRESTORE INITIALIZATION
// ============================================================================

let db;

async function initializeFirebase() {
  try {
    const serviceAccountPath = path.join(__dirname, 'google-play-service-account.json');
    
    if (!fs.existsSync(serviceAccountPath)) {
      console.error(`❌ ERROR: Service account file not found at ${serviceAccountPath}`);
      console.error('   Please ensure google-play-service-account.json exists in workspace root');
      process.exit(1);
    }

    const serviceAccount = require(serviceAccountPath);
    
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id,
      });
    }
    
    db = admin.firestore();
    console.log('✓ Firebase initialized successfully');
    return true;
  } catch (err) {
    console.error('❌ Firebase initialization failed:', err.message);
    process.exit(1);
  }
}

// ============================================================================
// DATA MIGRATION HELPERS
// ============================================================================

/**
 * Fetch all documents from a collection that lack tenant_id or have null tenant_id
 */
async function fetchDocsMissingTenantId(collectionName) {
  try {
    const snapshot = await db.collection(collectionName)
      .where('tenant_id', '==', null)
      .limit(1000)
      .get();
    
    if (snapshot.empty) {
      // Try fetching docs without tenant_id field at all
      const allSnapshot = await db.collection(collectionName).limit(1000).get();
      const docsMissingField = allSnapshot.docs.filter(doc => !doc.data().tenant_id);
      return docsMissingField;
    }
    
    return snapshot.docs;
  } catch (err) {
    console.error(`❌ Error fetching docs from ${collectionName}:`, err.message);
    return [];
  }
}

/**
 * Batch update documents with tenant_id
 */
async function batchUpdateDocs(collectionName, docs, tenantId) {
  let updated = 0;
  
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + BATCH_SIZE);
    
    for (const doc of chunk) {
      batch.update(doc.ref, { tenant_id: tenantId });
    }
    
    try {
      await batch.commit();
      updated += chunk.length;
      console.log(`  ✓ Updated ${updated}/${docs.length} docs in ${collectionName}`);
    } catch (err) {
      console.error(`❌ Batch update failed in ${collectionName}:`, err.message);
      throw err;
    }
  }
  
  return updated;
}

// ============================================================================
// DIAGNOSTIC FUNCTIONS
// ============================================================================

/**
 * Run pre-migration diagnostic checks
 */
async function runDiagnostics() {
  console.log('\n📋 Running Diagnostics...\n');
  
  // Check 1: Workspace exists
  try {
    const tenantDoc = await db.collection('tenants').doc(WORKSPACE_ID).get();
    if (tenantDoc.exists) {
      console.log(`✓ Workspace '${WORKSPACE_ID}' exists in /tenants`);
      console.log(`  Name: ${tenantDoc.data().name}`);
      console.log(`  Status: ${tenantDoc.data().active ? 'Active' : 'Inactive'}`);
    } else {
      console.warn(`⚠ WARNING: Workspace '${WORKSPACE_ID}' not found in /tenants`);
      console.warn('  Run firestore-diagnostic.js to verify workspace setup');
    }
  } catch (err) {
    console.error(`❌ Error checking workspace:`, err.message);
  }
  
  // Check 2: Count users without tenant_id
  try {
    const usersSnapshot = await db.collection('users')
      .where('tenant_id', '==', null)
      .get();
    console.log(`\n✓ Users with null tenant_id: ${usersSnapshot.size}`);
  } catch (err) {
    console.log(`\n⚠ Could not query users by null tenant_id (this is normal if field doesn't exist)`);
  }
  
  // Check 3: Sample user doc (to see structure)
  try {
    const sampleUser = await db.collection('users').limit(1).get();
    if (!sampleUser.empty) {
      const userData = sampleUser.docs[0].data();
      console.log(`\n📄 Sample user doc:`, sampleUser.docs[0].id);
      console.log(`  Has tenant_id: ${userData.tenant_id ? 'YES' : 'NO'}`);
      console.log(`  Current value: ${userData.tenant_id || '(missing)'}`);
    }
  } catch (err) {
    console.error(`❌ Error fetching sample user:`, err.message);
  }
}

// ============================================================================
// INTERACTIVE CONFIRMATION
// ============================================================================

function promptUserConfirmation(message) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    
    rl.question(message, (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === 'y');
    });
  });
}

// ============================================================================
// DRY-RUN (PREVIEW)
// ============================================================================

async function runDryRun() {
  console.log('\n🔍 DRY-RUN: Scanning documents to update...\n');
  
  const collections = ['users', 'customers', 'transactions', 'invoices'];
  const summary = {};
  
  for (const collectionName of collections) {
    const docs = await fetchDocsMissingTenantId(collectionName);
    summary[collectionName] = docs.length;
    
    if (docs.length > 0) {
      console.log(`\n📊 ${collectionName}: ${docs.length} docs missing tenant_id`);
      
      // Show first 3 doc IDs as preview
      const preview = docs.slice(0, 3).map(d => d.id).join(', ');
      console.log(`   Sample IDs: ${preview}${docs.length > 3 ? '...' : ''}`);
    } else {
      console.log(`\n✓ ${collectionName}: All docs have tenant_id set`);
    }
  }
  
  // Summary
  const totalToUpdate = Object.values(summary).reduce((a, b) => a + b, 0);
  console.log(`\n📈 TOTAL DOCUMENTS TO UPDATE: ${totalToUpdate}`);
  
  return { summary, totalToUpdate };
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

async function main() {
  console.log('\n========================================');
  console.log('  JBM Impex Workspace Data Migration');
  console.log(`  Target Workspace: ${WORKSPACE_ID}`);
  console.log('========================================\n');
  
  // Initialize Firebase
  await initializeFirebase();
  
  // Run diagnostics
  await runDiagnostics();
  
  // Run dry-run to show what will be updated
  const { summary, totalToUpdate } = await runDryRun();
  
  if (totalToUpdate === 0) {
    console.log('\n✅ All documents already have tenant_id set. No updates needed.');
    process.exit(0);
  }
  
  // Ask for confirmation
  console.log(`\n⚠️  This will update ${totalToUpdate} documents across multiple collections.`);
  const confirmed = await promptUserConfirmation('\nProceed with migration? (y/n): ');
  
  if (!confirmed) {
    console.log('\n❌ Migration cancelled.');
    process.exit(0);
  }
  
  // Execute migration
  console.log('\n🚀 Executing migration...\n');
  
  const collections = ['users', 'customers', 'transactions', 'invoices'];
  let totalUpdated = 0;
  
  for (const collectionName of collections) {
    if (summary[collectionName] === 0) continue;
    
    console.log(`\n📝 Updating ${collectionName}...`);
    const docs = await fetchDocsMissingTenantId(collectionName);
    const updated = await batchUpdateDocs(collectionName, docs, WORKSPACE_ID);
    totalUpdated += updated;
  }
  
  console.log(`\n✅ Migration complete! Updated ${totalUpdated} documents.`);
  console.log(`\n🎯 Next steps:`);
  console.log(`  1. Verify users can now see their workspace data after login`);
  console.log(`  2. Check Firestore Console: collections should now have tenant_id='${WORKSPACE_ID}'`);
  console.log(`  3. Run firestore-diagnostic.js again to verify migration success`);
}

main().catch(err => {
  console.error('\n❌ Migration failed:', err);
  process.exit(1);
});
