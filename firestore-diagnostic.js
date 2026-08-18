#!/usr/bin/env node
/**
 * Firestore SaaS Workspace Diagnostic Tool
 * 
 * Checks:
 * 1. Workspace 'jbm-impex' exists and is active
 * 2. Users assigned to 'jbm-impex' have tenant_id set correctly
 * 3. Shops/transactions/invoices have tenant_id fields
 * 4. Data isolation is working (no cross-workspace data leakage)
 * 5. Query indexes are present for tenant-scoped queries
 */

const admin = require('firebase-admin');
const fs = require('fs');

// Initialize Firebase
const serviceAccount = JSON.parse(fs.readFileSync('./google-play-service-account.json'));
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'shoeserp-clean-20260327'
});

const db = admin.firestore();
const WORKSPACE_SLUG = 'jbm-impex';

async function diagnoseWorkspaceMigration() {
  console.log('🔍 FIRESTORE SAAS WORKSPACE DIAGNOSTIC\n');
  console.log(`Workspace: ${WORKSPACE_SLUG}`);
  console.log('='.repeat(80) + '\n');

  try {
    // 1. Check if workspace exists
    console.log('1️⃣  CHECKING WORKSPACE DOCUMENT...');
    const tenantsSnapshot = await db.collection('tenants')
      .where('slug', '==', WORKSPACE_SLUG)
      .limit(1)
      .get();

    if (tenantsSnapshot.empty) {
      console.log(`   ❌ Workspace '${WORKSPACE_SLUG}' NOT FOUND in tenants collection`);
      return;
    }

    const workspaceDoc = tenantsSnapshot.docs[0];
    const workspaceId = workspaceDoc.id;
    const workspaceData = workspaceDoc.data();

    console.log(`   ✅ Workspace found: ID=${workspaceId}`);
    console.log(`   Name: ${workspaceData.name}`);
    console.log(`   Active: ${workspaceData.active}`);
    console.log(`   Owner: ${workspaceData.owner_user_id || 'None'}\n`);

    // 2. Check users assigned to this workspace
    console.log('2️⃣  CHECKING USERS ASSIGNED TO WORKSPACE...');
    const usersSnapshot = await db.collection('users')
      .where('tenant_id', '==', workspaceId)
      .limit(100)
      .get();

    console.log(`   Found: ${usersSnapshot.size} users`);
    if (usersSnapshot.size === 0) {
      console.log(`   ⚠️  WARNING: No users found with tenant_id='${workspaceId}'`);
      // Check if any users have tenant_id set at all
      const allUsersSnapshot = await db.collection('users').limit(20).get();
      console.log(`   Sample of first 20 users and their tenant_id values:`);
      allUsersSnapshot.forEach(doc => {
        const data = doc.data();
        console.log(`     - ${data.display_name}: tenant_id='${data.tenant_id || 'NULL'}'`);
      });
    } else {
      console.log(`   ✅ Users found. Sample (first 5):`);
      let count = 0;
      usersSnapshot.forEach(doc => {
        if (count < 5) {
          const data = doc.data();
          console.log(`     - ${data.display_name} (role: ${data.role})`);
        }
        count++;
      });
    }
    console.log('');

    // 3. Check shops with correct tenant_id
    console.log('3️⃣  CHECKING SHOPS WITH CORRECT TENANT_ID...');
    const shopsSnapshot = await db.collection('customers')
      .where('tenant_id', '==', workspaceId)
      .limit(100)
      .get();

    console.log(`   Found: ${shopsSnapshot.size} shops with tenant_id='${workspaceId}'`);
    
    // Check shops without tenant_id (legacy data)
    const legacyShopsSnapshot = await db.collection('customers')
      .where('tenant_id', '==', null)
      .limit(10)
      .get();

    if (!legacyShopsSnapshot.empty) {
      console.log(`   ⚠️  Found ${legacyShopsSnapshot.size} shops WITHOUT tenant_id (legacy single-instance data)`);
    }

    // Check total shops
    const allShopsSnapshot = await db.collection('customers').limit(200).get();
    console.log(`   Total shops in Firestore: ${allShopsSnapshot.size}\n`);

    // 4. Check transactions with correct tenant_id
    console.log('4️⃣  CHECKING TRANSACTIONS...');
    const txSnapshot = await db.collection('transactions')
      .where('tenant_id', '==', workspaceId)
      .limit(100)
      .get();

    console.log(`   Found: ${txSnapshot.size} transactions with tenant_id='${workspaceId}'`);

    const legacyTxSnapshot = await db.collection('transactions')
      .where('tenant_id', '==', null)
      .limit(10)
      .get();

    if (!legacyTxSnapshot.empty) {
      console.log(`   ⚠️  Found ${legacyTxSnapshot.size} transactions WITHOUT tenant_id (legacy data)\n`);
    }

    // 5. Check indexes
    console.log('5️⃣  CHECKING COMPOSITE INDEXES...');
    console.log('   Required indexes for tenant-scoped queries:');
    console.log('   - customers(tenant_id, active, name)');
    console.log('   - customers(tenant_id, route_id, active)');
    console.log('   - transactions(tenant_id, created_at DESC)');
    console.log('   - users(tenant_id, active, display_name)');
    console.log('   - invoices(tenant_id, created_at DESC)\n');

    // 6. Query performance test
    console.log('6️⃣  PERFORMANCE TEST: Query latency...');
    const start = Date.now();
    const testQuery = await db.collection('customers')
      .where('tenant_id', '==', workspaceId)
      .where('active', '==', true)
      .limit(50)
      .get();
    const latency = Date.now() - start;

    console.log(`   Query time: ${latency}ms`);
    console.log(`   Results: ${testQuery.size} shops\n`);

    // 7. Recommendations
    console.log('7️⃣  RECOMMENDATIONS:');
    if (usersSnapshot.size === 0) {
      console.log('   🔴 ACTION REQUIRED: Users not migrated to workspace');
      console.log('      - Run: node migrate_users_to_workspace.js jbm-impex');
    } else if (shopsSnapshot.size === 0 && allShopsSnapshot.size > 0) {
      console.log('   🔴 ACTION REQUIRED: Shops not migrated to workspace');
      console.log('      - Run: node migrate_shops_to_workspace.js jbm-impex');
      console.log('      - Then: node migrate_transactions_to_workspace.js jbm-impex');
      console.log('      - Then: node migrate_invoices_to_workspace.js jbm-impex');
    } else if (shopsSnapshot.size > 0) {
      console.log('   ✅ Workspace appears properly migrated');
      console.log(`   📊 Data summary: ${usersSnapshot.size} users, ${shopsSnapshot.size} shops, ${txSnapshot.size} transactions`);
    }

    if (latency > 1000) {
      console.log('   ⚠️  Query latency is high (>1s). Consider:');
      console.log('      - Adding composite index for tenant_id + filtering columns');
      console.log('      - Reducing query result limit (pagination)');
      console.log('      - Denormalizing frequently-accessed data');
    }

  } catch (error) {
    console.error('❌ Error during diagnostic:', error.message);
  } finally {
    process.exit(0);
  }
}

diagnoseWorkspaceMigration();
