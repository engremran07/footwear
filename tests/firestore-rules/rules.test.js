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
      ...extra,
    });
  });
}

async function seedShop(shopId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('customers').doc(shopId).set({
      name: 'Seed Shop',
      route_id: 'route-1',
      balance: 0,
      ...data,
    });
  });
}

async function seedSettings(data = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('settings').doc('global').set({
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
      adminCtx(testEnv).firestore().collection('users').get(),
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
});

// ═══════════════════════════════════════════════════════════════════════════
// 2. products collection
// ═══════════════════════════════════════════════════════════════════════════
describe('products collection', () => {
  it('seller (active): can read products', async () => {
    await seedUser('seller-uid', 'seller');
    await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('products').get(),
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
        active: true,
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
        balance: 0,
      }),
    );
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
      adminCtx(testEnv).firestore().collection('settings').get(),
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
      adminCtx(testEnv).firestore().collection('invoices').get(),
    );
  });

  it('seller: cannot create invoice with empty items list', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('invoices').doc('inv-1').set({
        created_by: 'seller-uid',
        shop_id: 'shop-1',
        route_id: 'route-1',
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
        shop_id: 'shop-1',
        route_id: 'route-1',
        seller_id: 'seller-uid',
        items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
        subtotal: 100,
        discount: 0,
        total: 100,
        amount_received: 0,
      }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 6. transactions collection
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
      });
    });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').delete(),
    );
  });

  it('admin: can delete transactions', async () => {
    await seedUser('admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('transactions').doc('tx1').set({
        seller_id: 'seller-uid',
        amount: 100,
        type: 'cash_in',
      });
    });
    await assertSucceeds(
      adminCtx(testEnv).firestore().collection('transactions').doc('tx1').delete(),
    );
  });

  it('seller: cannot directly update amount when approval is disabled', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ require_admin_approval_for_seller_transaction_edits: false });
    await seedTransaction('tx1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').update({
        amount: 999,
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
      }),
    );
  });
});
