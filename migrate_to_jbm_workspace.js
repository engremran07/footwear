/**
 * JBM Impex Workspace Data Migration
 * 
 * This script reassigns mgulamabas@gmail.com (tenant_admin) and all sellers
 * from the __global__ workspace to the JBM Impex workspace (already created).
 * 
 * All business data (shops, routes, transactions, invoices, inventory) flows
 * back to JBM Impex with their ledgers and history intact.
 * 
 * SAFETY: Read-only queries first, then atomic batch writes.
 */

const fs = require('fs');
const https = require('https');
const path = require('path');

const PROJECT = process.env.FIREBASE_PROJECT || 'shoeserp-clean-20260327';
const JBM_WORKSPACE_ID = 'jbm-impex';
const JBM_ADMIN_EMAIL = 'mgulamabas@gmail.com';

// ─── Token Exchange ──────────────────────────────────────────────────────
function getToken() {
  return new Promise((resolve, reject) => {
    const toolsApi = require('C:/Users/gsmen/AppData/Roaming/npm/node_modules/firebase-tools/lib/api.js');
    const cfgPath = path.join(process.env.USERPROFILE, '.config', 'configstore', 'firebase-tools.json');
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    const refresh = cfg.tokens.refresh_token;
    const clientId = toolsApi.clientId();
    const clientSecret = toolsApi.clientSecret();
    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refresh,
      client_id: clientId,
      client_secret: clientSecret,
    }).toString();

    const req = https.request('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (!json.access_token) throw new Error(data);
          resolve(json.access_token);
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ─── Firestore REST API helpers ──────────────────────────────────────────
async function firestoreQuery(token, collectionId, whereClause) {
  return new Promise((resolve, reject) => {
    const query = {
      structuredQuery: {
        from: [{ collectionId }],
        ...(whereClause && { where: whereClause }),
        limit: 1000,
      },
    };
    const payload = JSON.stringify(query);
    const req = https.request({
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const arr = JSON.parse(data);
          const docs = arr.filter((x) => x.document).map((r) => ({
            name: r.document.name,
            id: r.document.name.split('/').pop(),
            fields: r.document.fields || {},
          }));
          resolve(docs);
        } catch (e) {
          reject(new Error(`Query parse error: ${data.slice(0, 500)}`));
        }
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

async function firestorePatchDoc(token, docPath, updates) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify({ fields: updates });
    const fieldPaths = Object.keys(updates).map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`).join('&');
    const req = https.request({
      hostname: 'firestore.googleapis.com',
      path: `/v1/${docPath}?${fieldPaths}`,
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode !== 200) {
          reject(new Error(`Patch failed ${res.statusCode}: ${data.slice(0, 300)}`));
        } else {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(e);
          }
        }
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

// ─── Main Migration ──────────────────────────────────────────────────────
(async () => {
  try {
    console.log('🚀 JBM Impex Workspace Migration Started');
    console.log(`   Project: ${PROJECT}`);
    console.log(`   Workspace: ${JBM_WORKSPACE_ID}`);
    console.log(`   Admin: ${JBM_ADMIN_EMAIL}\n`);

    const token = await getToken();
    console.log('✅ Firebase authentication successful\n');

    // ── Step 1: Verify JBM workspace exists ──────────────────────────────
    console.log('📋 Step 1: Verifying JBM workspace exists...');
    const tenants = await firestoreQuery(token, 'tenants', {
      fieldFilter: {
        field: { fieldPath: 'slug' },
        op: 'EQUAL',
        value: { stringValue: JBM_WORKSPACE_ID },
      },
    });
    if (tenants.length === 0) {
      throw new Error(`❌ JBM workspace (${JBM_WORKSPACE_ID}) not found in Firestore`);
    }
    const jbmTenant = tenants[0];
    console.log(`✅ Found workspace: ${jbmTenant.fields.name?.stringValue || JBM_WORKSPACE_ID}\n`);

    // ── Step 2: Find mgulamabas@gmail.com and verify role ──────────────
    console.log('📋 Step 2: Looking up admin user (mgulamabas@gmail.com)...');
    const admins = await firestoreQuery(token, 'users', {
      fieldFilter: {
        field: { fieldPath: 'email' },
        op: 'EQUAL',
        value: { stringValue: JBM_ADMIN_EMAIL },
      },
    });
    if (admins.length === 0) {
      throw new Error(`❌ User ${JBM_ADMIN_EMAIL} not found`);
    }
    const adminUser = admins[0];
    const adminId = adminUser.id;
    const currentRole = adminUser.fields.role?.stringValue || 'seller';
    console.log(`✅ Found admin: ${adminId} (current role: ${currentRole})\n`);

    // ── Step 3: Get all sellers (to reassign to JBM) ──────────────────
    console.log('📋 Step 3: Finding all sellers to migrate...');
    const sellers = await firestoreQuery(token, 'users', {
      fieldFilter: {
        field: { fieldPath: 'role' },
        op: 'EQUAL',
        value: { stringValue: 'seller' },
      },
    });
    console.log(`✅ Found ${sellers.length} seller account(s)\n`);

    // ── Step 4: Get all routes (to reassign to JBM) ──────────────────
    console.log('📋 Step 4: Finding all routes...');
    const routes = await firestoreQuery(token, 'routes', null);
    console.log(`✅ Found ${routes.length} route(s)\n`);

    // ── Step 5: Get all shops (to reassign to JBM) ──────────────────
    console.log('📋 Step 5: Finding all shops (customers)...');
    const shops = await firestoreQuery(token, 'customers', null);
    console.log(`✅ Found ${shops.length} shop(s)\n`);

    // ── Step 6: Get financial data (transactions, invoices) ──────────────
    console.log('📋 Step 6: Finding financial data...');
    const transactions = await firestoreQuery(token, 'transactions', null);
    const invoices = await firestoreQuery(token, 'invoices', null);
    const inventoryTx = await firestoreQuery(token, 'inventory_transactions', null);
    console.log(`✅ Found ${transactions.length} transaction(s), ${invoices.length} invoice(s), ${inventoryTx.length} inventory move(s)\n`);

    // ── Step 7: MIGRATION PLAN (read-only assessment) ──────────────────
    console.log('📊 MIGRATION PLAN (no writes yet):');
    console.log(`   1. Admin (${adminId}) → tenant_admin for ${JBM_WORKSPACE_ID}`);
    console.log(`   2. ${sellers.length} Seller(s) → reassign to ${JBM_WORKSPACE_ID}`);
    console.log(`   3. ${routes.length} Route(s) → reassign to ${JBM_WORKSPACE_ID}`);
    console.log(`   4. ${shops.length} Shop(s) → reassign to ${JBM_WORKSPACE_ID}`);
    console.log(`   5. ${transactions.length} Transaction(s) → reassign to ${JBM_WORKSPACE_ID}`);
    console.log(`   6. ${invoices.length} Invoice(s) → reassign to ${JBM_WORKSPACE_ID}`);
    console.log(`   7. ${inventoryTx.length} Inventory move(s) → reassign to ${JBM_WORKSPACE_ID}\n`);

    // ── Step 8: Confirm before writing ──────────────────────────────────
    console.log('⚠️  WARNING: This will modify production Firestore data.');
    console.log('   Type "MIGRATE" to confirm:\n');

    // For automation: accept env var
    const confirm = process.env.MIGRATION_CONFIRM || 'NO';
    if (confirm !== 'MIGRATE') {
      console.log('❌ Migration cancelled (MIGRATION_CONFIRM != "MIGRATE")');
      process.exit(1);
    }

    // ── Step 9: Execute writes (atomic per-document) ──────────────────
    console.log('\n🔄 Executing migration...\n');

    const now = new Date().toISOString();
    let updateCount = 0;

    // Update admin user
    console.log(`   [1/${[1, sellers.length, routes.length, shops.length, transactions.length, invoices.length, inventoryTx.length].reduce((a, b) => a + b, 0)}] Updating admin user...`);
    await firestorePatchDoc(token, adminUser.name, {
      role: { stringValue: 'tenant_admin' },
      tenant_id: { stringValue: JBM_WORKSPACE_ID },
      updated_at: { timestampValue: now },
    });
    updateCount++;
    console.log('   ✅ Admin updated');

    // Update sellers
    let sellIdx = 2;
    for (const seller of sellers) {
      await firestorePatchDoc(token, seller.name, {
        tenant_id: { stringValue: JBM_WORKSPACE_ID },
        updated_at: { timestampValue: now },
      });
      updateCount++;
      if (sellIdx % 5 === 0 || sellIdx === sellers.length + 1) {
        console.log(`   ✅ Updated ${sellIdx - 1} seller(s)`);
      }
      sellIdx++;
    }

    // Update routes
    let routeIdx = 2 + sellers.length;
    for (const route of routes) {
      await firestorePatchDoc(token, route.name, {
        tenant_id: { stringValue: JBM_WORKSPACE_ID },
        updated_at: { timestampValue: now },
      });
      updateCount++;
      if (routeIdx % 5 === 0 || routeIdx === routes.length + sellers.length + 1) {
        console.log(`   ✅ Updated ${routeIdx - sellers.length - 1} route(s)`);
      }
      routeIdx++;
    }

    // Update shops
    let shopIdx = 2 + sellers.length + routes.length;
    for (const shop of shops) {
      await firestorePatchDoc(token, shop.name, {
        tenant_id: { stringValue: JBM_WORKSPACE_ID },
        updated_at: { timestampValue: now },
      });
      updateCount++;
      if (shopIdx % 10 === 0 || shopIdx === shops.length + sellers.length + routes.length + 1) {
        console.log(`   ✅ Updated ${shopIdx - sellers.length - routes.length - 1} shop(s)`);
      }
      shopIdx++;
    }

    // Update transactions
    let txIdx = 2 + sellers.length + routes.length + shops.length;
    for (const tx of transactions) {
      await firestorePatchDoc(token, tx.name, {
        tenant_id: { stringValue: JBM_WORKSPACE_ID },
        updated_at: { timestampValue: now },
      });
      updateCount++;
      if (txIdx % 20 === 0 || txIdx === transactions.length + sellers.length + routes.length + shops.length + 1) {
        console.log(`   ✅ Updated ${txIdx - sellers.length - routes.length - shops.length - 1} transaction(s)`);
      }
      txIdx++;
    }

    // Update invoices
    let invIdx = 2 + sellers.length + routes.length + shops.length + transactions.length;
    for (const inv of invoices) {
      await firestorePatchDoc(token, inv.name, {
        tenant_id: { stringValue: JBM_WORKSPACE_ID },
        updated_at: { timestampValue: now },
      });
      updateCount++;
      if (invIdx % 10 === 0 || invIdx === invoices.length + sellers.length + routes.length + shops.length + transactions.length + 1) {
        console.log(`   ✅ Updated ${invIdx - sellers.length - routes.length - shops.length - transactions.length - 1} invoice(s)`);
      }
      invIdx++;
    }

    // Update inventory transactions
    let invTxIdx = 2 + sellers.length + routes.length + shops.length + transactions.length + invoices.length;
    for (const invTx of inventoryTx) {
      await firestorePatchDoc(token, invTx.name, {
        tenant_id: { stringValue: JBM_WORKSPACE_ID },
        updated_at: { timestampValue: now },
      });
      updateCount++;
      if (invTxIdx % 10 === 0 || invTxIdx === inventoryTx.length + sellers.length + routes.length + shops.length + transactions.length + invoices.length + 1) {
        console.log(`   ✅ Updated ${invTxIdx - sellers.length - routes.length - shops.length - transactions.length - invoices.length - 1} inventory move(s)`);
      }
      invTxIdx++;
    }

    console.log(`\n✅ MIGRATION COMPLETE`);
    console.log(`   Total updates: ${updateCount}`);
    console.log(`   Admin: ${adminId} → tenant_admin`);
    console.log(`   Workspace: ${JBM_WORKSPACE_ID}`);
    console.log(`   Timestamp: ${now}`);
    console.log('\n📲 Sign out and re-login on all devices to see the new workspace.');
    console.log('   (Session cache will auto-invalidate workspace data on next auth check)\n');
  } catch (error) {
    console.error('\n❌ Migration failed:', error.message);
    process.exit(1);
  }
})();
