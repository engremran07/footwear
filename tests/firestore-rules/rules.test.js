/**
 * ShoesERP — Firestore Security Rules Emulator Tests
 *
 * These tests validate the permission matrix defined in AGENTS.md §3.
 * Run via: firebase emulators:exec --only firestore 'npm test'
 *
 * Collections under test:
 *   users, products, product_variants, seller_inventory,
 *   inventory_transactions, routes, customers (shops),
 *   transactions, invoices, settings
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const firebase = require('firebase/compat/app');
require('firebase/compat/firestore');
const { readFileSync } = require('fs');
const { resolve } = require('path');

const PROJECT_ID = 'shoeserp-clean-20260327';

let testEnv;

// ─── Helper: build authenticated context ────────────────────────────────────
function adminCtx(env) {
  return env.authenticatedContext('admin-uid', { email: 'admin@test.com' });
}
function sellerCtx(env) {
  return env.authenticatedContext('seller-uid', { email: 'seller@test.com' });
}
function anonCtx(env) {
  return env.unauthenticatedContext();
}

// ─── Before / After ─────────────────────────────────────────────────────────
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

// ─── Seed helpers ────────────────────────────────────────────────────────────
async function seedUser(uid, role, active = true, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({
      role,
      active,
      display_name: 'Test User',
      email: `${uid}@test.com`,
      tenant_id: 'tenant-1',
      assigned_route_ids: ['route-1'],
      ...extra,
    });
  });
}

async function seedShop(shopId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('customers').doc(shopId).set({
      name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      balance: 0,
      ...data,
    });
  });
}

async function seedSettings(data = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('settings').doc('tenant-1').set({
      tenant_id: 'tenant-1',
      require_admin_approval_for_seller_transaction_edits: false,
      show_arabic_column_names_in_english_reports: false,
      last_invoice_number: 0,
      ...data,
    });
  });
}

async function seedTransaction(txId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('transactions').doc(txId).set({
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      amount: 100,
      type: 'cash_in',
      description: 'seed',
      updated_at: new Date(),
      ...data,
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. USERS collection
// ═══════════════════════════════════════════════════════════════════════════
describe('users collection', () => {
  it('unauthenticated: denies read', async () => {
    await assertFails(anonCtx(testEnv).firestore().collection('users').get());
  });

  it('admin: can read users', async () => {
    await seedUser('admin-uid', 'admin');
    await assertSucceeds(
      adminCtx(testEnv).firestore()
        .collection('users')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
    );
  });

  it('seller: can read own user doc', async () => {
    await seedUser('seller-uid', 'seller');
    await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('users').doc('seller-uid').get(),
    );
  });

  it('seller: cannot read other user doc', async () => {
    await seedUser('seller-uid', 'seller');
    await seedUser('other-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('users').doc('other-uid').get(),
    );
  });

  it('admin: can create new user doc', async () => {
    await seedUser('admin-uid', 'admin');
    await assertSucceeds(
      adminCtx(testEnv).firestore().collection('users').doc('new-uid').set({
        role: 'seller',
        active: true,
        display_name: 'New Seller',
        email: 'new@test.com',
        tenant_id: 'tenant-1',
        created_by: 'admin-uid',
        assigned_route_ids: ['route-1'],
      }),
    );
  });

  it('seller: cannot create user doc', async () => {
    await seedUser('seller-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('users').doc('new-uid').set({
        role: 'seller',
        active: true,
        display_name: 'Hacked',
        email: 'hacked@test.com',
      }),
    );
  });

  it('client: cannot bootstrap a new admin account', async () => {
    const client = testEnv.authenticatedContext('bootstrap-uid').firestore();
    await assertFails(
      client.collection('users').doc('bootstrap-uid').set({
        role: 'admin',
        active: true,
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 2. products collection
// ═══════════════════════════════════════════════════════════════════════════
describe('products collection', () => {
  it('seller (active): can read products', async () => {
    await seedUser('seller-uid', 'seller');
    await assertSucceeds(
      sellerCtx(testEnv).firestore()
        .collection('products')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
    );
  });

  it('seller: cannot write products', async () => {
    await seedUser('seller-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('products').doc('p1').set({
        name: 'Hacked Product',
      }),
    );
  });

  it('admin: can write products', async () => {
    await seedUser('admin-uid', 'admin');
    await assertSucceeds(
      adminCtx(testEnv).firestore().collection('products').doc('p1').set({
        name: 'Test Product',
        active: true,
        tenant_id: 'tenant-1',
      }),
    );
  });

  it('admin: cannot create a product without a name', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore().collection('products').doc('p-empty').set({
        name: '',
        tenant_id: 'tenant-1',
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. routes collection
// ═══════════════════════════════════════════════════════════════════════════
describe('routes collection', () => {
  it('seller: cannot create routes', async () => {
    await seedUser('seller-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('routes').doc('r1').set({
        name: 'Hacked Route',
      }),
    );
  });

  it('admin: can create routes', async () => {
    await seedUser('admin-uid', 'admin');
    await assertSucceeds(
      adminCtx(testEnv).firestore().collection('routes').doc('r1').set({
        name: 'Test Route',
        route_number: 1,
        total_shops: 0,
        active: true,
        tenant_id: 'tenant-1',
      }),
    );
  });

  it('admin: cannot create a route with a negative route number', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore().collection('routes').doc('r-negative').set({
        name: 'Invalid Route',
        route_number: -1,
        total_shops: 0,
        tenant_id: 'tenant-1',
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 3a. product_variants collection
// ═══════════════════════════════════════════════════════════════════════════
describe('product_variants collection', () => {
  it('admin: cannot create a variant with negative stock', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore()
        .collection('product_variants')
        .doc('variant-negative')
        .set({
          product_id: 'product-1',
          variant_name: 'Size 40',
          quantity_available: -1,
          tenant_id: 'tenant-1',
        }),
    );
  });

  it('admin: cannot create a variant without product identity', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore()
        .collection('product_variants')
        .doc('variant-no-product')
        .set({
          product_id: '',
          variant_name: 'Size 40',
          quantity_available: 0,
          tenant_id: 'tenant-1',
        }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 3b. customers collection
// ═══════════════════════════════════════════════════════════════════════════
describe('customers collection', () => {
  it('seller: cannot create shop with empty name', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('customers').doc('shop-1').set({
        name: '',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        balance: 0,
      }),
    );
  });

  it('seller: can create shop in assigned route with valid name', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('customers').doc('shop-1').set({
        name: 'Valid Shop',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        balance: 0,
      }),
    );
  });

  it('seller: cannot create a shop with a non-zero balance', async () => {
    await seedUser('seller-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('customers').doc('shop-1').set({
        name: 'Seeded Debt',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        balance: 500,
      }),
    );
  });

  it('seller: cannot overwrite balance without a linked transaction', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('customers').doc('shop-1').update({
        balance: 0,
        updated_at: new Date(),
        last_transaction_at: new Date(),
        last_transaction_type: 'cash_in',
        last_transaction_amount: 100,
      }),
    );
  });

  it('seller: can create a transaction with its matching balance update atomically', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    const db = sellerCtx(testEnv).firestore();
    const txRef = db.collection('transactions').doc('tx-linked');
    const batch = db.batch();
    batch.set(txRef, {
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      amount: 25,
      type: 'cash_out',
      description: 'Linked sale',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 125,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 25,
      last_transaction_id: 'tx-linked',
    });
    await assertSucceeds(batch.commit());
  });

  it('seller: cannot mismatch linked transaction amount and balance delta', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    const db = sellerCtx(testEnv).firestore();
    const batch = db.batch();
    batch.set(db.collection('transactions').doc('tx-mismatch'), {
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      amount: 25,
      type: 'cash_out',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 1000,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 25,
      last_transaction_id: 'tx-mismatch',
    });
    await assertFails(batch.commit());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 4. settings collection
// ═══════════════════════════════════════════════════════════════════════════
describe('settings collection', () => {
  it('seller: cannot read settings', async () => {
    await seedUser('seller-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('settings').get(),
    );
  });

  it('admin: can read settings', async () => {
    await seedUser('admin-uid', 'admin');
    await assertSucceeds(
      adminCtx(testEnv).firestore().collection('settings').doc('tenant-1').get(),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 5. invoices collection
// ═══════════════════════════════════════════════════════════════════════════
describe('invoices collection', () => {
  it('unauthenticated: denies read invoices', async () => {
    await assertFails(
      anonCtx(testEnv).firestore().collection('invoices').get(),
    );
  });

  it('admin: can read all invoices', async () => {
    await seedUser('admin-uid', 'admin');
    await assertSucceeds(
      adminCtx(testEnv).firestore()
        .collection('invoices')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
    );
  });

  it('seller: cannot create invoice with empty items list', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('invoices').doc('inv-1').set({
        created_by: 'seller-uid',
        type: 'sale',
        shop_id: 'shop-1',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        seller_id: 'seller-uid',
        items: [],
        subtotal: 100,
        discount: 0,
        total: 100,
        amount_received: 0,
      }),
    );
  });

  it('seller: can create invoice with valid items and route ownership', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1');
    await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('invoices').doc('inv-1').set({
        created_by: 'seller-uid',
        type: 'sale',
        shop_id: 'shop-1',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        seller_id: 'seller-uid',
        items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
        subtotal: 100,
        discount: 0,
        total: 100,
        amount_received: 0,
      }),
    );
  });

  it('seller: invoice sale links its net balance change to same-batch ledger entries', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('inv-linked');
    const saleRef = db.collection('transactions').doc('tx-sale');
    const paymentRef = db.collection('transactions').doc('tx-payment');
    const batch = db.batch();
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'sale',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 25,
      payment_transaction_id: paymentRef.id,
    });
    batch.set(saleRef, {
      created_by: 'seller-uid',
      type: 'cash_out',
      amount: 100,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    batch.set(paymentRef, {
      created_by: 'seller-uid',
      type: 'cash_in',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 175,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 100,
      last_transaction_id: saleRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('seller: cannot reduce invoice balance for an unrecorded payment', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('inv-unlinked-payment');
    const saleRef = db.collection('transactions').doc('tx-unlinked-sale');
    const batch = db.batch();
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'sale',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 25,
    });
    batch.set(saleRef, {
      created_by: 'seller-uid',
      type: 'cash_out',
      amount: 100,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 175,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 100,
      last_transaction_id: saleRef.id,
    });
    await assertFails(batch.commit());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 6. Super-admin-only destructive operations
// ═══════════════════════════════════════════════════════════════════════════
describe('tenant destructive operations', () => {
  const targetCollections = [
    'users',
    'products',
    'product_variants',
    'seller_inventory',
    'inventory_transactions',
    'routes',
    'customers',
    'transactions',
    'invoices',
    'settings',
    'tenants',
  ];

  async function seedDeleteTargets() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const collection of targetCollections) {
        const docId = collection === 'settings' || collection === 'tenants'
          ? 'tenant-1'
          : `delete-target-${collection}`;
        await db.collection(collection).doc(docId).set({
          tenant_id: 'tenant-1',
          active: true,
          role: 'seller',
          name: 'Seed record',
        });
      }
    });
  }

  it('workspace admins and sellers cannot hard-delete tenant data', async () => {
    await seedDeleteTargets();
    for (const role of ['tenant_admin', 'admin', 'manager', 'seller']) {
      const uid = `delete-${role}-uid`;
      await seedUser(uid, role);
      const db = testEnv.authenticatedContext(uid).firestore();
      for (const collection of targetCollections) {
        const docId = collection === 'settings' || collection === 'tenants'
          ? 'tenant-1'
          : `delete-target-${collection}`;
        await assertFails(db.collection(collection).doc(docId).delete());
      }
    }
  });

  it('selected super-admin can hard-delete only selected-tenant data', async () => {
    await seedDeleteTargets();
    await seedUser('delete-platform-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Approved workspace cleanup',
      active_workspace_selected_at: new Date(),
    });
    const db = testEnv.authenticatedContext('delete-platform-uid').firestore();
    for (const collection of targetCollections) {
      const docId = collection === 'settings' || collection === 'tenants'
        ? 'tenant-1'
        : `delete-target-${collection}`;
      await assertSucceeds(db.collection(collection).doc(docId).delete());
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 7. transactions collection
// ═══════════════════════════════════════════════════════════════════════════
describe('transactions collection', () => {
  it('seller: cannot delete transactions', async () => {
    await seedUser('seller-uid', 'seller');
    // Seed a transaction doc first
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('transactions').doc('tx1').set({
        seller_id: 'seller-uid',
        amount: 100,
        type: 'cash_in',
        tenant_id: 'tenant-1',
      });
    });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').delete(),
    );
  });

  it('selected super-admin: can delete transactions in active tenant', async () => {
    await seedUser('platform-delete-tx-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Approved workspace cleanup',
      active_workspace_selected_at: new Date(),
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('transactions').doc('tx1').set({
        seller_id: 'seller-uid',
        amount: 100,
        type: 'cash_in',
        tenant_id: 'tenant-1',
      });
    });
    await assertSucceeds(
      testEnv.authenticatedContext('platform-delete-tx-uid')
        .firestore()
        .collection('transactions')
        .doc('tx1')
        .delete(),
    );
  });

  it('seller: cannot update amount without atomic shop balance correction', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ require_admin_approval_for_seller_transaction_edits: false });
    await seedShop('shop-1', { balance: 100 });
    await seedTransaction('tx1', { type: 'cash_out', amount: 100 });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').update({
        amount: 999,
      }),
    );
  });

  it('seller: cannot edit amount even with a matching balance correction', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ require_admin_approval_for_seller_transaction_edits: false });
    await seedShop('shop-1', { balance: 100 });
    await seedTransaction('tx1', { type: 'cash_out', amount: 100 });
    const db = sellerCtx(testEnv).firestore();
    const batch = db.batch();
    batch.update(db.collection('transactions').doc('tx1'), { amount: 120 });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 120,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 120,
      last_transaction_id: 'tx1',
    });
    await assertFails(batch.commit());
  });

  it('seller: can annotate own transaction without changing financial fields', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ require_admin_approval_for_seller_transaction_edits: false });
    await seedTransaction('tx1');
    await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').update({
        description: 'Receipt note',
        updated_at: new Date(),
      }),
    );
  });

  it('seller: can submit edit request metadata when approval is enabled', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ require_admin_approval_for_seller_transaction_edits: true });
    await seedTransaction('tx1');
    await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').update({
        description: 'Need correction',
        updated_at: new Date(),
        updated_by: 'seller-uid',
        edit_request_pending: true,
        edit_request_status: 'pending',
        edit_request_requested_by: 'seller-uid',
        edit_request_requested_at: new Date(),
        edit_request_new_amount: 120,
        edit_request_new_type: 'cash_in',
        edit_request_new_description: 'Need correction',
        edit_request_new_sale_type: 'cash',
        edit_request_new_created_at: new Date(),
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 7. inventory_transactions collection
// ═══════════════════════════════════════════════════════════════════════════
describe('inventory_transactions collection', () => {
  it('seller: cannot create inventory transaction with invalid type', async () => {
    await seedUser('seller-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('inventory_transactions').doc('it1').set({
        type: 'unknown',
        seller_id: 'seller-uid',
        created_by: 'seller-uid',
        quantity: 12,
      }),
    );
  });

  it('seller: can create inventory transaction with valid type', async () => {
    await seedUser('seller-uid', 'seller');
    await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('inventory_transactions').doc('it1').set({
        type: 'return_to_warehouse',
        seller_id: 'seller-uid',
        created_by: 'seller-uid',
        quantity: 12,
        tenant_id: 'tenant-1',
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 8. notifications collection
// ═══════════════════════════════════════════════════════════════════════════
describe('notifications collection', () => {
  it('seller: cannot create notifications without atomic rate state', async () => {
    await seedUser('seller-uid', 'seller');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('notifications').doc('n1').set({
        created_by: 'seller-uid',
        tenant_id: 'tenant-1',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('seller: can create a notification once per cooldown window', async () => {
    await seedUser('seller-uid', 'seller');
    const db = sellerCtx(testEnv).firestore();
    const batch = db.batch();
    batch.set(db.collection('notifications').doc('n1'), {
      created_by: 'seller-uid',
      tenant_id: 'tenant-1',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('users').doc('seller-uid'), {
      last_notification_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(batch.commit());

    const rapidBatch = db.batch();
    rapidBatch.set(db.collection('notifications').doc('n2'), {
      created_by: 'seller-uid',
      tenant_id: 'tenant-1',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    rapidBatch.update(db.collection('users').doc('seller-uid'), {
      last_notification_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertFails(rapidBatch.commit());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 9. Platform super-admin workspace isolation
// ═══════════════════════════════════════════════════════════════════════════
describe('platform super-admin workspace isolation', () => {
  const businessCollections = [
    'users',
    'products',
    'product_variants',
    'seller_inventory',
    'inventory_transactions',
    'routes',
    'customers',
    'transactions',
    'invoices',
  ];

  async function seedWorkspace(tenantId) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('tenants').doc(tenantId).set({
        tenant_id: tenantId,
        name: tenantId,
        active: true,
      });
    });
  }

  async function seedBusinessCollections(tenantIds) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const tenantId of tenantIds) {
        for (const collection of businessCollections) {
          await db.collection(collection).doc(`${tenantId}-${collection}`).set({
            tenant_id: tenantId,
            active: true,
            role: 'seller',
            name: `${tenantId} record`,
          });
        }
        await db.collection('settings').doc(tenantId).set({
          tenant_id: tenantId,
          company_name: tenantId,
        });
      }
    });
  }

  it('unselected super-admin cannot read business collections', async () => {
    await seedUser('platform-unselected-uid', 'super_admin');
    await seedBusinessCollections(['tenant-1']);
    const db = testEnv.authenticatedContext('platform-unselected-uid').firestore();
    for (const collection of businessCollections) {
      await assertFails(
        db.collection(collection).where('tenant_id', '==', 'tenant-1').get(),
      );
    }
    await assertFails(db.collection('settings').doc('tenant-1').get());
  });

  it('selected super-admin is limited to the selected tenant', async () => {
    await seedBusinessCollections(['tenant-a', 'tenant-b']);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const batch = db.batch();
      batch.set(db.collection('tenants').doc('tenant-a'), {
        tenant_id: 'tenant-a', name: 'Tenant A', active: true,
      });
      batch.set(db.collection('tenants').doc('tenant-b'), {
        tenant_id: 'tenant-b', name: 'Tenant B', active: true,
      });
      batch.set(db.collection('users').doc('platform-selected-uid'), {
        role: 'super_admin',
        active: true,
        active_workspace_id: 'tenant-a',
        active_workspace_reason: 'Support ticket investigation',
        active_workspace_selected_at: new Date(),
      });
      await batch.commit();
    });
    const db = testEnv.authenticatedContext('platform-selected-uid').firestore();
    for (const collection of businessCollections) {
      await assertSucceeds(
        db.collection(collection).where('tenant_id', '==', 'tenant-a').get(),
      );
      await assertFails(
        db.collection(collection).where('tenant_id', '==', 'tenant-b').get(),
      );
    }
    await assertSucceeds(db.collection('settings').doc('tenant-a').get());
    await assertFails(db.collection('settings').doc('tenant-b').get());
  });

  it('selected super-admin cannot read a different tenant', async () => {
    await seedWorkspace('tenant-a');
    await seedWorkspace('tenant-b');
    await seedUser('platform-cross-tenant-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: new Date(),
    });
    await seedBusinessCollections(['tenant-a', 'tenant-b']);
    await assertFails(
      testEnv.authenticatedContext('platform-cross-tenant-uid')
        .firestore()
        .collection('products')
        .where('tenant_id', '==', 'tenant-b')
        .get(),
    );
  });

  it('super-admin cannot access another tenant user profile', async () => {
    await seedWorkspace('tenant-a');
    await seedWorkspace('tenant-b');
    await seedUser('platform-user-read-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: new Date(),
    });
    await seedUser('tenant-b-user', 'seller', true, {
      tenant_id: 'tenant-b',
    });
    await assertFails(
      testEnv.authenticatedContext('platform-user-read-uid')
        .firestore()
        .collection('users')
        .doc('tenant-b-user')
        .get(),
    );
  });

  it('client cannot create another platform super-admin', async () => {
    await seedWorkspace('tenant-a');
    await seedUser('platform-role-create-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Platform operations review',
      active_workspace_selected_at: new Date(),
    });
    await assertFails(
      testEnv.authenticatedContext('platform-uid')
        .firestore()
        .collection('users')
        .doc('new-platform-admin')
        .set({
          role: 'super_admin',
          tenant_id: 'tenant-a',
          created_by: 'platform-role-create-uid',
          active: true,
        }),
    );
  });

  it('support access audit logs are append-only and cannot be read by tenants', async () => {
    await seedWorkspace('tenant-a');
    await seedUser('platform-audit-uid', 'super_admin');
    await seedUser('tenant-admin-uid', 'tenant_admin', true, {
      tenant_id: 'tenant-a',
    });
    const platformDb = testEnv.authenticatedContext('platform-audit-uid').firestore();
    await assertSucceeds(
      platformDb.collection('platform_access_logs').doc('log-1').set({
        actor_user_id: 'platform-audit-uid',
        workspace_id: 'tenant-a',
        event_type: 'workspace_access_started',
        reason: 'Support ticket investigation',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertFails(
      platformDb.collection('platform_access_logs').doc('log-1').update({
        reason: 'Changed reason',
      }),
    );
    await assertFails(
      platformDb.collection('platform_access_logs').doc('log-1').delete(),
    );
    await assertFails(
      testEnv.authenticatedContext('tenant-admin-uid')
        .firestore()
        .collection('platform_access_logs')
        .doc('log-1')
        .get(),
    );
  });

  it('client cannot read admin_config credentials', async () => {
    await seedUser('platform-credential-read-uid', 'super_admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('admin_config').doc('sa_credentials').set({
        placeholder: true,
      });
    });
    await assertFails(
      testEnv.authenticatedContext('platform-credential-read-uid')
        .firestore()
        .collection('admin_config')
        .doc('sa_credentials')
        .get(),
    );
  });
});
