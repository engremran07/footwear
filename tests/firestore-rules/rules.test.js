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
const assert = require('assert');
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

async function seedTenant({
  tenantId = 'tenant-1',
  ownerUserId = 'tenant-admin-uid',
  maxDevicesAllowed = 2,
  maxActiveSessionsAllowed = 2,
  includeTenantId = true,
  includeLimits = true,
  requireDevicePairing = false,
  allowAdminResetOnly = true,
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('tenants').doc(tenantId).set({
      ...(includeTenantId ? { tenant_id: tenantId } : {}),
      owner_user_id: ownerUserId,
      active: true,
      ...(includeLimits ? {
        max_devices_allowed: maxDevicesAllowed,
        max_active_sessions_allowed: maxActiveSessionsAllowed,
      } : {}),
      require_device_pairing: requireDevicePairing,
      allow_admin_reset_only: allowAdminResetOnly,
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

  it('admin: cannot create a tenant administrator', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore().collection('users').doc('new-tenant-admin').set({
        role: 'tenant_admin',
        active: true,
        display_name: 'New Workspace Admin',
        email: 'workspace-admin@test.com',
        tenant_id: 'tenant-1',
        created_by: 'admin-uid',
      }),
    );
  });

  it('admin: cannot promote a seller to tenant administrator', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('target-uid', 'seller');
    await assertFails(
      adminCtx(testEnv).firestore().collection('users').doc('target-uid').update({
        role: 'tenant_admin',
        updated_at: new Date(),
      }),
    );
  });

  it('admin: cannot deactivate a tenant administrator', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await assertFails(
      adminCtx(testEnv).firestore().collection('users').doc('tenant-admin-uid').update({
        active: false,
        updated_at: new Date(),
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

  it('seller: cannot read workspace products after the workspace is disabled', async () => {
    await seedTenant();
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('products').doc('workspace-disabled-product').set({
        name: 'Disabled workspace product',
        tenant_id: 'tenant-1',
      });
      await db.collection('tenants').doc('tenant-1').update({ active: false });
      await db.collection('users').doc('seller-uid').update({ active: false });
    });

    await assertFails(
      sellerCtx(testEnv).firestore()
        .collection('products')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
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

  it('admin: cannot create a credit note for a missing original invoice', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore().collection('invoices').doc('credit-missing').set({
        tenant_id: 'tenant-1',
        type: 'credit_note',
        linked_invoice_id: 'missing-original',
        shop_id: 'shop-1',
        route_id: 'route-1',
        items: [{ variant_id: 'variant-1', qty: 1, unit_price: 50 }],
        subtotal: 50,
        discount: 0,
        total: 50,
        amount_received: 0,
      }),
    );
  });

  it('admin: can create a linked credit note without exceeding original total', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 100 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('original-sale').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        credit_note_total: 0,
      });
    });
    const db = adminCtx(testEnv).firestore();
    const batch = db.batch();
    const creditRef = db.collection('invoices').doc('credit-valid');
    const returnRef = db.collection('transactions').doc('credit-valid-tx');
    batch.update(db.collection('invoices').doc('original-sale'), {
      credit_note_total: 40,
    });
    batch.set(creditRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'credit_note',
      return_transaction_id: returnRef.id,
      linked_invoice_id: 'original-sale',
      shop_id: 'shop-1',
      route_id: 'route-1',
      items: [{ variant_id: 'variant-1', qty: 1, unit_price: 40 }],
      subtotal: 40,
      discount: 0,
      total: 40,
      amount_received: 0,
    });
    batch.set(returnRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'return',
      amount: 40,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: creditRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 60,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'return',
      last_transaction_amount: 40,
      last_transaction_id: returnRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('admin: cannot create a credit note without its return transaction and shop update', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 100 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('original-sale').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        credit_note_total: 0,
      });
    });
    const db = adminCtx(testEnv).firestore();
    const batch = db.batch();
    batch.update(db.collection('invoices').doc('original-sale'), {
      credit_note_total: 40,
    });
    batch.set(db.collection('invoices').doc('credit-orphan'), {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'credit_note',
      linked_invoice_id: 'original-sale',
      shop_id: 'shop-1',
      route_id: 'route-1',
      items: [{ variant_id: 'variant-1', qty: 1, unit_price: 40 }],
      subtotal: 40,
      discount: 0,
      total: 40,
      amount_received: 0,
    });
    await assertFails(batch.commit());
  });

  it('admin: cannot cumulatively credit more than the original total', async () => {
    await seedUser('admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('original-sale').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        credit_note_total: 80,
      });
    });
    const db = adminCtx(testEnv).firestore();
    const batch = db.batch();
    batch.update(db.collection('invoices').doc('original-sale'), {
      credit_note_total: 110,
    });
    batch.set(db.collection('invoices').doc('credit-over-limit'), {
      tenant_id: 'tenant-1',
      type: 'credit_note',
      linked_invoice_id: 'original-sale',
      shop_id: 'shop-1',
      route_id: 'route-1',
      items: [{ variant_id: 'variant-1', qty: 1, unit_price: 30 }],
      subtotal: 30,
      discount: 0,
      total: 30,
      amount_received: 0,
    });
    await assertFails(batch.commit());
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
    await seedShop('shop-1', { balance: 0 });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('seller_inventory').doc('inventory-1').set({
        seller_id: 'seller-uid',
        tenant_id: 'tenant-1',
        quantity_available: 5,
      });
    });
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('inv-1');
    const saleRef = db.collection('transactions').doc('tx-inv-1');
    const batch = db.batch();
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'sale',
      invoice_number: 'INV-2026-0001',
      sale_transaction_id: saleRef.id,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      fulfillment_mode: 'stock',
      seller_inventory_deductions: { 'inventory-1': 1 },
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 0,
    });
    batch.set(saleRef, {
      created_by: 'seller-uid',
      type: 'cash_out',
      amount: 100,
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-0001',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 100,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 100,
      last_transaction_id: saleRef.id,
    });
    batch.update(db.collection('seller_inventory').doc('inventory-1'), {
      quantity_available: 4,
      updated_at: new Date(),
      last_sale_invoice_id: invoiceRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('seller: cannot create a sale invoice without its ledger and balance writes', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1', { balance: 0 });
    const invoiceRef = sellerCtx(testEnv).firestore()
      .collection('invoices').doc('orphan-sale');

    await assertFails(invoiceRef.set({
      created_by: 'seller-uid',
      type: 'sale',
      fulfillment_mode: 'stock',
      seller_inventory_deductions: { 'inventory-1': 1 },
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 0,
    }));
  });

  it('admin: cannot create a sale invoice without its ledger and balance writes', async () => {
    await seedTenant();
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 0 });
    await seedSettings({ allow_non_stock_invoices: true });
    const invoiceRef = adminCtx(testEnv).firestore()
      .collection('invoices').doc('orphan-admin-sale');

    await assertFails(invoiceRef.set({
      created_by: 'admin-uid',
      type: 'sale',
      fulfillment_mode: 'non_stock',
      seller_inventory_deductions: {},
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'admin-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 0,
    }));
  });

  it('admin: cannot create a linked sale invoice without changing shop balance', async () => {
    await seedTenant();
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 10 });
    await seedSettings({ allow_non_stock_invoices: true });
    const db = adminCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('admin-orphan-balance');
    const saleRef = db.collection('transactions').doc('admin-orphan-sale-tx');
    const batch = db.batch();
    batch.set(invoiceRef, {
      created_by: 'admin-uid',
      type: 'sale',
      invoice_number: 'INV-2026-0003',
      sale_transaction_id: saleRef.id,
      fulfillment_mode: 'non_stock',
      seller_inventory_deductions: {},
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'admin-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 0,
    });
    batch.set(saleRef, {
      created_by: 'admin-uid',
      type: 'cash_out',
      amount: 100,
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-0003',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
    });

    await assertFails(batch.commit());
  });

  it('admin: can atomically create a partial sale with both ledger rows and balance', async () => {
    await seedTenant();
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 20 });
    await seedSettings({ allow_non_stock_invoices: true });
    const db = adminCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('admin-partial-sale');
    const saleRef = db.collection('transactions').doc('admin-partial-sale-out');
    const paymentRef = db.collection('transactions').doc('admin-partial-sale-in');
    const batch = db.batch();
    batch.set(invoiceRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      invoice_number: 'INV-2026-ADMIN-PARTIAL',
      sale_transaction_id: saleRef.id,
      payment_transaction_id: paymentRef.id,
      type: 'sale',
      fulfillment_mode: 'non_stock',
      seller_inventory_deductions: {},
      shop_id: 'shop-1',
      route_id: 'route-1',
      seller_id: 'admin-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 25,
    });
    batch.set(saleRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'cash_out',
      amount: 100,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-ADMIN-PARTIAL',
    });
    batch.set(paymentRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'cash_in',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-ADMIN-PARTIAL',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 95,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 100,
      last_transaction_id: saleRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('admin: can settle a partial sale invoice with its cash-in and balance update', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 75 });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('invoices').doc('partial-sale').set({
        tenant_id: 'tenant-1',
        created_by: 'seller-uid',
        type: 'sale',
        status: 'partial',
        invoice_number: 'INV-2026-PARTIAL',
        shop_id: 'shop-1',
        route_id: 'route-1',
        total: 100,
        amount_received: 25,
        outstanding_amount: 75,
      });
    });

    const db = adminCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('partial-sale');
    const paymentRef = db.collection('transactions').doc('settlement-tx');
    const batch = db.batch();
    batch.update(invoiceRef, {
      status: 'paid',
      amount_received: 100,
      outstanding_amount: 0,
      updated_at: new Date(),
    });
    batch.set(paymentRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'cash_in',
      amount: 75,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 0,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_in',
      last_transaction_amount: 75,
      last_transaction_id: paymentRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('admin: can void a partially paid sale with a linked cash refund', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 75 });
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('invoices').doc('void-sale').set({
        tenant_id: 'tenant-1',
        created_by: 'seller-uid',
        type: 'sale',
        status: 'partial',
        invoice_number: 'INV-2026-VOID',
        shop_id: 'shop-1',
        route_id: 'route-1',
        total: 100,
        amount_received: 25,
        outstanding_amount: 75,
      });
    });

    const db = adminCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('void-sale');
    const reversalRef = db.collection('transactions').doc('void-return-tx');
    const refundRef = db.collection('transactions').doc('void-refund-tx');
    const batch = db.batch();
    batch.update(invoiceRef, {
      status: 'void',
      void_by: 'admin-uid',
      void_at: new Date(),
      updated_at: new Date(),
    });
    batch.set(reversalRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'return',
      amount: 100,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
    });
    batch.set(refundRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'cash_out',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 0,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 25,
      last_transaction_id: refundRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('seller: cannot create a stock invoice without inventory deductions', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('invoices').doc('inv-no-stock').set({
        created_by: 'seller-uid',
        type: 'sale',
        fulfillment_mode: 'stock',
        seller_inventory_deductions: {},
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

  it('seller: can create non-stock invoice when the workspace allows it', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1', { balance: 0 });
    await seedSettings({ allow_non_stock_invoices: true });
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('inv-non-stock');
    const saleRef = db.collection('transactions').doc('tx-non-stock');
    const batch = db.batch();
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'sale',
      invoice_number: 'INV-2026-0002',
      sale_transaction_id: saleRef.id,
      fulfillment_mode: 'non_stock',
      seller_inventory_deductions: {},
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 0,
    });
    batch.set(saleRef, {
      created_by: 'seller-uid',
      type: 'cash_out',
      amount: 100,
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-0002',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 100,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 100,
      last_transaction_id: saleRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('seller: cannot create non-stock invoice when the workspace disables it', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1');
    await seedSettings({ allow_non_stock_invoices: false });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('invoices').doc('inv-disabled').set({
        created_by: 'seller-uid',
        type: 'sale',
        fulfillment_mode: 'non_stock',
        seller_inventory_deductions: {},
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

  it('seller: cannot create non-stock invoice when workspace setting is absent', async () => {
    await seedTenant();
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('invoices').doc('inv-no-setting').set({
        created_by: 'seller-uid',
        type: 'sale',
        fulfillment_mode: 'non_stock',
        seller_inventory_deductions: {},
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

  it('seller: cannot override the workspace invoice header snapshot', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1');
    await seedSettings({
      company_name: 'Tenant Shop',
      invoice_header: { name_en: 'Tenant Shop', visible_fields: [] },
    });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('invoices').doc('inv-forged-header').set({
        created_by: 'seller-uid',
        type: 'sale',
        fulfillment_mode: 'stock',
        seller_inventory_deductions: { 'inventory-1': 1 },
        invoice_header_snapshot: {
          name_en: 'Tenant Shop',
          visible_fields: [],
          company_name: 'Imposter Shop',
        },
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

  it('seller: can atomically create a linked cash receipt and reduce shop balance', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    await seedSettings();
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('receipt-1');
    const transactionRef = db.collection('transactions').doc('receipt-tx');
    const batch = db.batch();
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_cash_receipt_number: 1,
    });
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'cash_receipt',
      fulfillment_mode: 'none',
      cash_receipt_transaction_id: transactionRef.id,
      cash_receipt_sequence: 1,
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [],
      subtotal: 0,
      discount: 0,
      total: 25,
      amount_received: 25,
      status: 'paid',
    });
    batch.set(transactionRef, {
      created_by: 'seller-uid',
      type: 'cash_in',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 75,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_in',
      last_transaction_amount: 25,
      last_transaction_id: transactionRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('seller: cannot create a cash receipt without advancing its workspace sequence', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    await seedSettings();
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('receipt-without-sequence');
    const transactionRef = db.collection('transactions').doc('receipt-tx');
    const batch = db.batch();
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'cash_receipt',
      fulfillment_mode: 'none',
      cash_receipt_transaction_id: transactionRef.id,
      cash_receipt_sequence: 1,
      invoice_number: 'REC-2026-0001',
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [],
      subtotal: 0,
      discount: 0,
      total: 25,
      amount_received: 25,
      status: 'paid',
    });
    batch.set(transactionRef, {
      created_by: 'seller-uid',
      type: 'cash_in',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 75,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_in',
      last_transaction_amount: 25,
      last_transaction_id: transactionRef.id,
    });
    await assertFails(batch.commit());
  });

  it('seller: cannot create a cash receipt without its shop balance update', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    await seedSettings();
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('receipt-no-shop-update');
    const transactionRef = db.collection('transactions').doc('receipt-no-shop-update-tx');
    const batch = db.batch();
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_cash_receipt_number: 1,
    });
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'cash_receipt',
      fulfillment_mode: 'none',
      cash_receipt_transaction_id: transactionRef.id,
      cash_receipt_sequence: 1,
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [],
      subtotal: 0,
      discount: 0,
      total: 25,
      amount_received: 25,
      status: 'paid',
    });
    batch.set(transactionRef, {
      created_by: 'seller-uid',
      type: 'cash_in',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    await assertFails(batch.commit());
  });

  it('seller: cannot apply a cash receipt with mismatched invoice linkage', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('receipt-unlinked');
    const transactionRef = db.collection('transactions').doc('receipt-tx');
    const batch = db.batch();
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'cash_receipt',
      fulfillment_mode: 'none',
      cash_receipt_transaction_id: 'different-tx',
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      items: [],
      subtotal: 0,
      discount: 0,
      total: 25,
      amount_received: 25,
      status: 'paid',
    });
    batch.set(transactionRef, {
      created_by: 'seller-uid',
      type: 'cash_in',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 75,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_in',
      last_transaction_amount: 25,
      last_transaction_id: transactionRef.id,
    });
    await assertFails(batch.commit());
  });

  it('seller: cannot create a cash receipt invoice without its cash-in transaction', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('invoices').doc('receipt-orphan').set({
        created_by: 'seller-uid',
        type: 'cash_receipt',
        fulfillment_mode: 'none',
        cash_receipt_transaction_id: 'missing-tx',
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        seller_id: 'seller-uid',
        items: [],
        subtotal: 0,
        discount: 0,
        total: 25,
        amount_received: 25,
        status: 'paid',
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
      invoice_number: 'INV-2026-0001',
      sale_transaction_id: saleRef.id,
      fulfillment_mode: 'stock',
      seller_inventory_deductions: { 'inventory-1': 1 },
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
      invoice_number: 'INV-2026-0001',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      invoice_id: invoiceRef.id,
    });
    batch.set(paymentRef, {
      created_by: 'seller-uid',
      type: 'cash_in',
      amount: 25,
      invoice_number: 'INV-2026-0001',
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
      fulfillment_mode: 'stock',
      seller_inventory_deductions: { 'inventory-1': 1 },
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
  it('admin: cannot overwrite financial fields without an edit history entry', async () => {
    await seedUser('admin-uid', 'admin');
    await seedTransaction('tx-admin-edit', {
      created_at: new Date('2026-01-01T00:00:00.000Z'),
    });
    await assertFails(
      adminCtx(testEnv).firestore()
        .collection('transactions')
        .doc('tx-admin-edit')
        .update({ amount: 120, updated_at: new Date() }),
    );
  });

  it('admin: can correct financial fields with a matching append-only history entry', async () => {
    await seedUser('admin-uid', 'admin');
    const createdAt = new Date('2026-01-01T00:00:00.000Z');
    await seedTransaction('tx-admin-edit-history', {
      created_at: createdAt,
      description: 'Original entry',
    });
    await assertSucceeds(
      adminCtx(testEnv).firestore()
        .collection('transactions')
        .doc('tx-admin-edit-history')
        .update({
          amount: 120,
          updated_at: new Date(),
          edit_history: [{
            previous_amount: 100,
            previous_type: 'cash_in',
            previous_created_at: createdAt,
            previous_description: 'Original entry',
            changed_by: 'admin-uid',
            reason: 'Receipt amount correction',
            changed_at: new Date(),
          }],
        }),
    );
  });

  it('seller: cannot create a transaction with a foreign or missing tenant', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1');
    const db = sellerCtx(testEnv).firestore();

    for (const [index, tenantId] of [
      ['foreign', 'tenant-2'],
      ['null', null],
      ['missing', undefined],
    ]) {
      const data = {
        shop_id: 'shop-1',
        route_id: 'route-1',
        created_by: 'seller-uid',
        amount: 25,
        type: 'cash_in',
        ...(tenantId === undefined ? {} : { tenant_id: tenantId }),
      };
      await assertFails(
        db.collection('transactions').doc(`tx-invalid-tenant-${index}`).set(data),
      );
    }
  });

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
describe('seller inventory quantity controls', () => {
  async function seedSellerInventory() {
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('seller_inventory').doc('seller-uid_variant-1').set({
        seller_id: 'seller-uid',
        tenant_id: 'tenant-1',
        quantity_available: 20,
        active: true,
      });
    });
  }

  it('seller: cannot increase own stock', async () => {
    await seedSellerInventory();
    await assertFails(
      sellerCtx(testEnv).firestore()
        .collection('seller_inventory')
        .doc('seller-uid_variant-1')
        .update({ quantity_available: 9999 }),
    );
  });

  it('seller: can decrease own stock for a sale', async () => {
    await seedSellerInventory();
    await seedShop('shop-1', { balance: 0 });
    const db = sellerCtx(testEnv).firestore();
    const batch = db.batch();
    const invoiceRef = db.collection('invoices').doc('sale-linked-stock');
    const saleRef = db.collection('transactions').doc('sale-linked-stock-tx');
    batch.update(db.collection('seller_inventory').doc('seller-uid_variant-1'), {
      quantity_available: 12,
      last_sale_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      invoice_number: 'INV-2026-STOCK-1',
      sale_transaction_id: saleRef.id,
      seller_id: 'seller-uid',
      type: 'sale',
      fulfillment_mode: 'stock',
      shop_id: 'shop-1',
      route_id: 'route-1',
      items: [{ variant_id: 'variant-1', qty: 8, unit_price: 10 }],
      subtotal: 80,
      discount: 0,
      total: 80,
      amount_received: 0,
      seller_inventory_deductions: { 'seller-uid_variant-1': 8 },
    });
    batch.set(saleRef, {
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      type: 'cash_out',
      amount: 80,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-STOCK-1',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 80,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 80,
      last_transaction_id: saleRef.id,
    });
    await assertSucceeds(batch.commit());
  });

  it('seller: cannot silently decrease stock without a matching invoice', async () => {
    await seedSellerInventory();
    await assertFails(
      sellerCtx(testEnv).firestore()
        .collection('seller_inventory')
        .doc('seller-uid_variant-1')
        .update({ quantity_available: 12 }),
    );
  });

  it('admin: cannot set seller inventory below zero', async () => {
    await seedUser('admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('seller_inventory').doc('seller-uid_variant-1').set({
        seller_id: 'seller-uid',
        tenant_id: 'tenant-1',
        quantity_available: 4,
        active: true,
      });
    });
    await assertFails(
      adminCtx(testEnv).firestore()
        .collection('seller_inventory')
        .doc('seller-uid_variant-1')
        .update({ quantity_available: -1 }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// Device and session slot access controls
// ═══════════════════════════════════════════════════════════════════════════
describe('device and session slot rules', () => {
  function deviceData(slotNumber, overrides = {}) {
    return {
      user_id: 'seller-uid',
      tenant_id: 'tenant-1',
      slot_id: `slot_${slotNumber}`,
      slot_number: slotNumber,
      device_id: `installation-${slotNumber}`,
      brand: 'Samsung',
      model: 'SM-A576B',
      platform: 'android',
      os_version: '16',
      app_version: 'test',
      status: 'active',
      registered_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      ...overrides,
    };
  }

  function sessionData(slotNumber, overrides = {}) {
    return {
      user_id: 'seller-uid',
      tenant_id: 'tenant-1',
      slot_id: `slot_${slotNumber}`,
      slot_number: slotNumber,
      session_id: `session-${slotNumber}`,
      device_slot_id: `slot_${slotNumber}`,
      device_id: `installation-${slotNumber}`,
      device_brand: 'Samsung',
      device_model: 'SM-A576B',
      platform: 'android',
      status: 'active',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      expires_at: new Date(Date.now() + 60 * 60 * 1000),
      ...overrides,
    };
  }

  async function seedAccessUsers() {
    await seedTenant();
    await seedTenant({ tenantId: 'tenant-2' });
    await seedUser('seller-uid', 'seller');
    await seedUser('other-seller-uid', 'seller');
    await seedUser('tenant-admin-uid', 'tenant_admin');
  }

  async function seedWorkspaceAdminPolicy() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('settings')
        .doc('platform_access_policy').set({
          workspace_admin_max_devices_allowed: 3,
          workspace_admin_max_active_sessions_allowed: 2,
        });
    });
  }

  it('workspace admin can disable and re-enable a seller while revoking sessions', async () => {
    await seedAccessUsers();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const seller = ctx.firestore().collection('users').doc('seller-uid');
      await seller.collection('device_registrations').doc('slot_0')
        .set(deviceData(0));
      await seller.collection('sessions').doc('slot_0')
        .set(sessionData(0));
      await seller.collection('device_registrations').doc('slot_1')
        .set(deviceData(1));
      await seller.collection('sessions').doc('slot_1')
        .set(sessionData(1));
    });

    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const sellerRef = db.collection('users').doc('seller-uid');
    await db.runTransaction(async (transaction) => {
      const userSnapshot = await transaction.get(sellerRef);
      const sessionRefs = [0, 1].map((slot) =>
        sellerRef.collection('sessions').doc(`slot_${slot}`));
      const sessionSnapshots = await Promise.all(
        sessionRefs.map((sessionRef) => transaction.get(sessionRef)));
      assert.strictEqual(userSnapshot.data().tenant_id, 'tenant-1');
      transaction.update(sellerRef, {
        active: false,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      });
      sessionSnapshots.forEach((sessionSnapshot) => {
        if (sessionSnapshot.data().status !== 'active') return;
        transaction.update(sessionSnapshot.ref, {
          status: 'revoked',
          revoked_at: firebase.firestore.FieldValue.serverTimestamp(),
          termination_reason: 'account_disabled',
          terminated_by: 'tenant-admin-uid',
        });
      });
    });
    await assertSucceeds(sellerRef.update({
      active: true,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    }));
    for (const slot of [0, 1]) {
      const session = await sellerRef.collection('sessions')
        .doc(`slot_${slot}`).get();
      assert.strictEqual(session.data().status, 'revoked');
    }
  });

  it('workspace admin cannot disable self, peer admins, or another tenant seller', async () => {
    await seedAccessUsers();
    await seedUser('peer-admin-uid', 'tenant_admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc('other-seller-uid').update({
        tenant_id: 'tenant-2',
      });
    });

    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const updatedAt = firebase.firestore.FieldValue.serverTimestamp();
    await assertFails(db.collection('users').doc('tenant-admin-uid').update({
      active: false,
      updated_at: updatedAt,
    }));
    await assertFails(db.collection('users').doc('peer-admin-uid').update({
      active: false,
      updated_at: updatedAt,
    }));
    await assertFails(db.collection('users').doc('other-seller-uid').update({
      active: false,
      updated_at: updatedAt,
    }));
  });

  it('seller can get only their own workspace document for session registration', async () => {
    await seedAccessUsers();
    const db = sellerCtx(testEnv).firestore();
    await assertSucceeds(db.collection('tenants').doc('tenant-1').get());
    await assertFails(db.collection('tenants').doc('tenant-2').get());
    await assertFails(db.collection('tenants').get());
  });

  it('workspace admin can read missing access slots only for users in their tenant', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    await seedUser('other-seller-uid', 'seller', true, {
      tenant_id: 'tenant-2',
    });
    const db = adminCtx(testEnv).firestore();
    await assertSucceeds(
      db.collection('users')
        .doc('seller-uid')
        .collection('device_registrations')
        .doc('slot_8')
        .get(),
    );
    await assertSucceeds(
      db.collection('users')
        .doc('seller-uid')
        .collection('sessions')
        .doc('slot_8')
        .get(),
    );
    await assertFails(
      db.collection('users')
        .doc('other-seller-uid')
        .collection('sessions')
        .doc('slot_8')
        .get(),
    );
  });

  it('allows a seller to read an unused own access slot before registration', async () => {
    await seedAccessUsers();
    const db = sellerCtx(testEnv).firestore();
    const userRef = db.collection('users').doc('seller-uid');
    await assertSucceeds(
      userRef.collection('device_registrations').doc('slot_0').get(),
    );
    await assertSucceeds(userRef.collection('sessions').doc('slot_0').get());
  });

  it('allows only tenant-and-user-scoped session queries', async () => {
    await seedAccessUsers();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const userRef = ctx.firestore().collection('users').doc('seller-uid');
      await userRef.collection('sessions').doc('slot_0').set(sessionData(0));
    });
    const sessions = sellerCtx(testEnv).firestore()
      .collection('users').doc('seller-uid').collection('sessions');

    await assertFails(sessions.get());
    await assertSucceeds(
      sessions
        .where('tenant_id', '==', 'tenant-1')
        .where('user_id', '==', 'seller-uid')
        .get(),
    );
  });

  it('seller can sign in again on the same device after logout', async () => {
    await seedTenant({ requireDevicePairing: true });
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const userRef = context.firestore().collection('users').doc('seller-uid');
      await userRef.collection('device_registrations').doc('slot_0')
        .set(deviceData(0, { status: 'active' }));
      await userRef.collection('sessions').doc('slot_0').set(sessionData(0, {
        status: 'revoked',
        revoked_at: new Date(),
        termination_reason: 'logout',
        terminated_by: 'seller-uid',
      }));
    });

    const db = sellerCtx(testEnv).firestore();
    const userRef = db.collection('users').doc('seller-uid');
    const batch = db.batch();
    batch.update(userRef.collection('device_registrations').doc('slot_0'), {
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      app_version: 'recheck',
    });
    batch.set(userRef.collection('sessions').doc('slot_0'), sessionData(0, {
      session_id: 'session-after-logout',
    }));

    await assertSucceeds(batch.commit());
  });

  it('workspace admin can sign in again on the same device after logout', async () => {
    await seedTenant({ requireDevicePairing: true });
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedWorkspaceAdminPolicy();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const userRef = context.firestore().collection('users')
        .doc('tenant-admin-uid');
      await userRef.collection('device_registrations').doc('slot_0')
        .set(deviceData(0, {
          user_id: 'tenant-admin-uid',
          status: 'active',
        }));
      await userRef.collection('sessions').doc('slot_0').set(sessionData(0, {
        user_id: 'tenant-admin-uid',
        status: 'revoked',
        revoked_at: new Date(),
        termination_reason: 'logout',
        terminated_by: 'tenant-admin-uid',
      }));
    });

    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const userRef = db.collection('users').doc('tenant-admin-uid');
    const batch = db.batch();
    batch.update(userRef.collection('device_registrations').doc('slot_0'), {
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      app_version: 'recheck',
    });
    batch.set(userRef.collection('sessions').doc('slot_0'), sessionData(0, {
      user_id: 'tenant-admin-uid',
      session_id: 'session-after-logout',
    }));

    await assertSucceeds(batch.commit());
  });

  it('allows workspace admins to query only their own access-record groups', async () => {
    await seedAccessUsers();
    await seedUser('registry-admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_0').set(sessionData(0));
      await db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0').set(deviceData(0));
    });

    const adminDb = testEnv.authenticatedContext('registry-admin-uid').firestore();
    const sellerDb = sellerCtx(testEnv).firestore();
    await assertSucceeds(
      adminDb.collectionGroup('sessions')
        .where('tenant_id', '==', 'tenant-1').get(),
    );
    await assertSucceeds(
      adminDb.collectionGroup('device_registrations')
        .where('tenant_id', '==', 'tenant-1').get(),
    );
    await assertFails(
      sellerDb.collectionGroup('sessions')
        .where('tenant_id', '==', 'tenant-1').get(),
    );
  });

  it('accepts legacy tenant policy documents without a duplicated tenant_id', async () => {
    await seedTenant({ includeTenantId: false });
    await seedUser('seller-uid', 'seller');
    const userRef = sellerCtx(testEnv).firestore()
      .collection('users').doc('seller-uid');
    await assertSucceeds(userRef.collection('device_registrations').doc('slot_0')
      .set(deviceData(0)));
    await assertSucceeds(userRef.collection('sessions').doc('slot_0')
      .set(sessionData(0)));
  });

  it('workspace admin device pairing uses the platform cap, not seller approval', async () => {
    await seedTenant({ requireDevicePairing: true });
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedWorkspaceAdminPolicy();
    const adminDb = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const deviceRef = adminDb.collection('users').doc('tenant-admin-uid')
      .collection('device_registrations').doc('slot_0');

    await assertSucceeds(deviceRef.set(deviceData(0, {
      user_id: 'tenant-admin-uid',
      status: 'active',
    })));
    await assertFails(
      adminDb.collection('users').doc('tenant-admin-uid')
        .collection('device_registrations').doc('slot_1')
        .set(deviceData(1, {
          user_id: 'tenant-admin-uid',
          status: 'pending',
        })),
    );
  });

  it('workspace admin uses default platform caps when policy is absent', async () => {
    await seedTenant({ requireDevicePairing: true });
    await seedUser('tenant-admin-uid', 'tenant_admin');
    const deviceRef = testEnv.authenticatedContext('tenant-admin-uid')
      .firestore().collection('users').doc('tenant-admin-uid')
      .collection('device_registrations').doc('slot_0');

    await assertSucceeds(deviceRef.set(deviceData(0, {
      user_id: 'tenant-admin-uid',
      status: 'active',
    })));
  });

  it('workspace admin can resume a pending own device without approval metadata', async () => {
    await seedTenant({ requireDevicePairing: true });
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedWorkspaceAdminPolicy();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('users').doc('tenant-admin-uid')
        .collection('device_registrations').doc('slot_0')
        .set(deviceData(0, {
          user_id: 'tenant-admin-uid',
          status: 'pending',
        }));
    });
    const deviceRef = testEnv.authenticatedContext('tenant-admin-uid')
      .firestore().collection('users').doc('tenant-admin-uid')
      .collection('device_registrations').doc('slot_0');

    await assertSucceeds(deviceRef.update({
      status: 'active',
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      app_version: '3.9.75+102',
    }));
  });

  it('workspace admin cannot approve their own pending device', async () => {
    await seedTenant({ requireDevicePairing: true });
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('users').doc('tenant-admin-uid')
        .collection('device_registrations').doc('slot_0')
        .set(deviceData(0, {
          user_id: 'tenant-admin-uid',
          status: 'pending',
        }));
    });
    const deviceRef = testEnv.authenticatedContext('tenant-admin-uid')
      .firestore().collection('users').doc('tenant-admin-uid')
      .collection('device_registrations').doc('slot_0');

    await assertFails(deviceRef.update({
      status: 'active',
      approved_at: firebase.firestore.FieldValue.serverTimestamp(),
      approved_by: 'tenant-admin-uid',
    }));
  });

  it('enforces required device approval before session creation', async () => {
    await seedTenant({ requireDevicePairing: true });
    await seedUser('seller-uid', 'seller');
    await seedUser('tenant-admin-uid', 'tenant_admin');
    const sellerDb = sellerCtx(testEnv).firestore();
    const userRef = sellerDb.collection('users').doc('seller-uid');
    await assertSucceeds(
      userRef.collection('device_registrations').doc('slot_0')
        .set(deviceData(0, { status: 'pending' })),
    );
    await assertFails(
      userRef.collection('sessions').doc('slot_0').set(sessionData(0)),
    );

    await testEnv.authenticatedContext('tenant-admin-uid').firestore()
      .collection('users').doc('seller-uid')
      .collection('device_registrations').doc('slot_0')
      .update({
        status: 'active',
        approved_at: firebase.firestore.FieldValue.serverTimestamp(),
        approved_by: 'tenant-admin-uid',
      });
    await assertSucceeds(
      userRef.collection('sessions').doc('slot_0').set(sessionData(0)),
    );
  });

  it('prevents owners and administrators from reactivating blocked devices', async () => {
    await seedAccessUsers();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0')
        .set(deviceData(0, { status: 'blocked' }));
    });
    const sellerDevice = sellerCtx(testEnv).firestore()
      .collection('users').doc('seller-uid')
      .collection('device_registrations').doc('slot_0');
    await assertFails(sellerDevice.update({
      status: 'active',
      registered_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
    }));
    const adminDevice = testEnv.authenticatedContext('tenant-admin-uid')
      .firestore().collection('users').doc('seller-uid')
      .collection('device_registrations').doc('slot_0');
    await assertFails(adminDevice.update({
      status: 'active',
      approved_at: firebase.firestore.FieldValue.serverTimestamp(),
      approved_by: 'tenant-admin-uid',
    }));
  });

  it('allows an owner to reclaim a device registration inactive for 30 days', async () => {
    await seedAccessUsers();
    const staleAt = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0')
        .set(deviceData(0, { last_seen_at: staleAt }));
    });
    const device = sellerCtx(testEnv).firestore()
      .collection('users').doc('seller-uid')
      .collection('device_registrations').doc('slot_0');
    await assertSucceeds(
      device.set(deviceData(0, {
        device_id: 'replacement-installation',
        registered_at: firebase.firestore.FieldValue.serverTimestamp(),
        last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      })),
    );
  });

  it('uses three device and two session slots when legacy policy fields are absent', async () => {
    await seedTenant({ includeTenantId: false, includeLimits: false });
    await seedUser('seller-uid', 'seller');
    const userRef = sellerCtx(testEnv).firestore()
      .collection('users').doc('seller-uid');
    for (let slot = 0; slot < 3; slot++) {
      await assertSucceeds(
        userRef.collection('device_registrations').doc(`slot_${slot}`)
          .set(deviceData(slot)),
      );
    }
    for (let slot = 0; slot < 2; slot++) {
      await assertSucceeds(
        userRef.collection('sessions').doc(`slot_${slot}`)
          .set(sessionData(slot)),
      );
    }
    await assertFails(
      userRef.collection('sessions').doc('slot_2').set(sessionData(2)),
    );
  });

  it('allows moderate client-clock skew but rejects excessive session expiry', async () => {
    await seedAccessUsers();
    const db = sellerCtx(testEnv).firestore();
    const userRef = db.collection('users').doc('seller-uid');
    await userRef.collection('device_registrations').doc('slot_0')
      .set(deviceData(0));
    await assertSucceeds(
      userRef.collection('sessions').doc('slot_0').set(
        sessionData(0, { expires_at: new Date(Date.now() + 11 * 60 * 60 * 1000) }),
      ),
    );
    await assertFails(
      userRef.collection('sessions').doc('slot_1').set(
        sessionData(1, {
          device_slot_id: 'slot_0',
          expires_at: new Date(Date.now() + 13 * 60 * 60 * 1000),
        }),
      ),
    );
  });

  it('seller can allocate own device and session slots within policy', async () => {
    await seedAccessUsers();
    const db = sellerCtx(testEnv).firestore();
    await assertSucceeds(
      db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0')
        .set(deviceData(0)),
    );
    await assertSucceeds(
      db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_0')
        .set(sessionData(0)),
    );
  });

  it('seller cannot allocate beyond the workspace limits', async () => {
    await seedTenant({ maxDevicesAllowed: 1, maxActiveSessionsAllowed: 1 });
    await seedUser('seller-uid', 'seller');
    const db = sellerCtx(testEnv).firestore();
    await assertFails(
      db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_1')
        .set(deviceData(1)),
    );
    await assertFails(
      db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_1')
        .set(sessionData(1)),
    );
  });

  it('cannot forge a low slot number in a higher slot document path', async () => {
    await seedTenant({ maxDevicesAllowed: 1, maxActiveSessionsAllowed: 1 });
    await seedUser('seller-uid', 'seller');
    const db = sellerCtx(testEnv).firestore();
    await assertFails(
      db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_9')
        .set(deviceData(0, { slot_id: 'slot_9' })),
    );
    await assertFails(
      db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_9')
        .set(sessionData(0, { slot_id: 'slot_9' })),
    );
  });

  it('rejects arbitrary document IDs even when the slot number is within policy', async () => {
    await seedAccessUsers();
    const db = sellerCtx(testEnv).firestore();
    await assertFails(
      db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('custom-device-0')
        .set(deviceData(0, { slot_id: 'custom-device-0' })),
    );
    await assertFails(
      db.collection('users').doc('seller-uid')
        .collection('sessions').doc('custom-session-0')
        .set(sessionData(0, { slot_id: 'custom-session-0' })),
    );
  });

  it('requires sessions to reference an active device with the same installation ID', async () => {
    await seedAccessUsers();
    const db = sellerCtx(testEnv).firestore();
    const userRef = db.collection('users').doc('seller-uid');
    await assertFails(
      userRef.collection('sessions').doc('slot_0').set(sessionData(0)),
    );
    await userRef.collection('device_registrations').doc('slot_0')
      .set(deviceData(0));
    await assertFails(
      userRef.collection('sessions').doc('slot_0').set(
        sessionData(0, { device_id: 'another-installation' }),
      ),
    );
    await assertSucceeds(
      userRef.collection('sessions').doc('slot_0').set(sessionData(0)),
    );
  });

  it('links legacy sessions to their active device on refresh', async () => {
    await seedAccessUsers();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0').set(deviceData(0));
      const legacySession = sessionData(0);
      delete legacySession.device_slot_id;
      await db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_0').set(legacySession);
    });

    const sessionRef = sellerCtx(testEnv).firestore()
      .collection('users').doc('seller-uid')
      .collection('sessions').doc('slot_0');
    await assertSucceeds(
      sessionRef.update({
        device_slot_id: 'slot_0',
        last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
        expires_at: new Date(Date.now() + 60 * 60 * 1000),
      }),
    );
  });

  it('seller cannot read or write another user access records', async () => {
    await seedAccessUsers();
    const db = sellerCtx(testEnv).firestore();
    const otherDevices = db.collection('users').doc('other-seller-uid')
      .collection('device_registrations');
    await assertFails(otherDevices.get());
    await assertFails(otherDevices.doc('slot_0').set(deviceData(0, {
      user_id: 'other-seller-uid',
    })));
  });

  it('seller cannot change workspace access policy', async () => {
    await seedAccessUsers();
    await assertFails(
      sellerCtx(testEnv).firestore().collection('tenants').doc('tenant-1')
        .update({ max_devices_allowed: 10 }),
    );
  });

  it('tenant admins can edit seller limits but not pairing policy; selected super-admin can', async () => {
    await seedAccessUsers();
    const tenantAdminDb = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    await assertSucceeds(
      tenantAdminDb.collection('tenants').doc('tenant-1').update({
        max_devices_allowed: 3,
        max_active_sessions_allowed: 4,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertFails(
      tenantAdminDb.collection('tenants').doc('tenant-1').update({
        require_device_pairing: true,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await seedUser('platform-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Approved policy administration',
      active_workspace_selected_at: new Date(),
    });
    const db = testEnv.authenticatedContext('platform-uid').firestore();
    await assertSucceeds(db.collection('tenants').doc('tenant-1').update({
      max_devices_allowed: 3,
      max_active_sessions_allowed: 4,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    }));
    await assertFails(
      db.collection('tenants').doc('tenant-1').update({
        max_devices_allowed: 11,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('platform super-admin controls global workspace-admin access limits', async () => {
    await seedAccessUsers();
    await seedUser('platform-uid', 'super_admin');
    const platformPolicy = testEnv.authenticatedContext('platform-uid')
      .firestore().collection('settings').doc('platform_access_policy');
    await assertSucceeds(platformPolicy.set({
      workspace_admin_max_devices_allowed: 3,
      workspace_admin_max_active_sessions_allowed: 2,
      updated_by: 'platform-uid',
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    }));

    const tenantAdminDb = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    await assertSucceeds(
      tenantAdminDb.collection('settings').doc('platform_access_policy').get(),
    );
    await assertFails(
      tenantAdminDb.collection('settings').doc('platform_access_policy').update({
        workspace_admin_max_devices_allowed: 10,
        updated_by: 'tenant-admin-uid',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertFails(
      sellerCtx(testEnv).firestore()
        .collection('settings').doc('platform_access_policy').get(),
    );
  });

  it('workspace admins use the platform-wide access cap, not seller caps', async () => {
    await seedTenant({ maxDevicesAllowed: 1, maxActiveSessionsAllowed: 1 });
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('platform-uid', 'super_admin');
    await testEnv.authenticatedContext('platform-uid').firestore()
      .collection('settings').doc('platform_access_policy').set({
        workspace_admin_max_devices_allowed: 3,
        workspace_admin_max_active_sessions_allowed: 2,
        updated_by: 'platform-uid',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const userRef = db.collection('users').doc('tenant-admin-uid');
    for (let slot = 0; slot < 3; slot++) {
      await assertSucceeds(
        userRef.collection('device_registrations').doc(`slot_${slot}`).set(
          deviceData(slot, { user_id: 'tenant-admin-uid' }),
        ),
      );
    }
    await assertFails(
      userRef.collection('device_registrations').doc('slot_3').set(
        deviceData(3, { user_id: 'tenant-admin-uid' }),
      ),
    );
    for (let slot = 0; slot < 2; slot++) {
      await assertSucceeds(
        userRef.collection('sessions').doc(`slot_${slot}`).set(
          sessionData(slot, { user_id: 'tenant-admin-uid' }),
        ),
      );
    }
    await assertFails(
      userRef.collection('sessions').doc('slot_2').set(
        sessionData(2, { user_id: 'tenant-admin-uid' }),
      ),
    );
  });

  it('workspace admin can revoke a device and related session atomically', async () => {
    await seedAccessUsers();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0').set({
          ...deviceData(0),
          registered_at: new Date(),
          last_seen_at: new Date(),
        });
      await db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_0').set({
          ...sessionData(0),
          created_at: new Date(),
          last_seen_at: new Date(),
          expires_at: new Date(Date.now() + 60 * 60 * 1000),
        });
    });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const batch = db.batch();
    batch.update(
      db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0'),
      {
        status: 'revoked',
        revoked_at: firebase.firestore.FieldValue.serverTimestamp(),
        revoked_by: 'tenant-admin-uid',
      },
    );
    batch.update(
      db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_0'),
      {
        status: 'revoked',
        revoked_at: firebase.firestore.FieldValue.serverTimestamp(),
        termination_reason: 'device_revoked',
        terminated_by: 'tenant-admin-uid',
      },
    );
    await assertSucceeds(
      batch.commit(),
    );
  });
});

describe('platform operator sessions', () => {
  it('allows two fixed platform slots and denies other users or excess devices', async () => {
    await seedUser('platform-admin-uid', 'super_admin');
    await seedUser('other-platform-admin-uid', 'super_admin');
    const session = {
      user_id: 'platform-admin-uid',
      session_id: 'platform-session-123',
      slot_id: 'slot_0',
      slot_number: 0,
      device_id: 'platform-installation-1',
      device_brand: 'Microsoft',
      device_model: 'Surface',
      platform: 'windows',
      status: 'active',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      expires_at: new Date(Date.now() + 60 * 60 * 1000),
    };
    const ownSessions = testEnv.authenticatedContext('platform-admin-uid')
      .firestore().collection('users').doc('platform-admin-uid')
      .collection('platform_sessions');
    await assertSucceeds(ownSessions.doc('slot_0').set(session));
    await assertSucceeds(ownSessions.where('user_id', '==', 'platform-admin-uid').get());
    await assertFails(ownSessions.doc('slot_1').set({
      ...session,
      session_id: 'platform-session-456',
      slot_id: 'slot_1',
      slot_number: 1,
      device_id: 'platform-installation-2',
    }));
    await assertSucceeds(ownSessions.doc('slot_0').update({
      status: 'revoked',
      revoked_at: firebase.firestore.FieldValue.serverTimestamp(),
      terminated_by: 'platform-admin-uid',
    }));
    await assertSucceeds(ownSessions.doc('slot_1').set({
      ...session,
      session_id: 'platform-session-456',
      slot_id: 'slot_1',
      slot_number: 1,
      device_id: 'platform-installation-2',
    }));
    await assertFails(ownSessions.doc('slot_2').set({
      ...session,
      session_id: 'platform-session-789',
      slot_id: 'slot_2',
      slot_number: 2,
    }));
    await assertFails(
      testEnv.authenticatedContext('other-platform-admin-uid').firestore()
        .collection('users').doc('platform-admin-uid')
        .collection('platform_sessions').doc('slot_0').get(),
    );
  });

  it('allows a super-admin to reactivate the same platform slot after logout', async () => {
    await seedUser('platform-admin-uid', 'super_admin');
    const session = {
      user_id: 'platform-admin-uid',
      session_id: 'platform-session-123',
      slot_id: 'slot_0',
      slot_number: 0,
      device_id: 'platform-installation-1',
      device_brand: 'Samsung',
      device_model: 'SM-A576B',
      platform: 'android',
      status: 'active',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_seen_at: firebase.firestore.FieldValue.serverTimestamp(),
      expires_at: new Date(Date.now() + 60 * 60 * 1000),
    };
    const slot = testEnv.authenticatedContext('platform-admin-uid')
      .firestore().collection('users').doc('platform-admin-uid')
      .collection('platform_sessions').doc('slot_0');

    await assertSucceeds(slot.set(session));
    await assertSucceeds(slot.update({
      status: 'revoked',
      revoked_at: firebase.firestore.FieldValue.serverTimestamp(),
      terminated_by: 'platform-admin-uid',
    }));
    await assertSucceeds(slot.set({
      ...session,
      session_id: 'platform-session-456',
    }));
  });
});

describe('inventory_transactions collection', () => {
  it('admin: cannot create a stock audit row without tenant identity', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore().collection('inventory_transactions').doc('it-missing-tenant').set({
        type: 'stock_adjustment',
        seller_id: '',
        seller_name: 'warehouse',
        product_id: 'product-1',
        variant_id: 'variant-1',
        variant_name: 'Size 40',
        quantity: 5,
        direction: 'in',
        created_by: 'admin-uid',
        created_at: new Date(),
      }),
    );
  });

  it('admin: can transfer stock when every written document carries its tenant', async () => {
    await seedUser('admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('product_variants').doc('variant-1').set({
        tenant_id: 'tenant-1',
        quantity_available: 20,
        product_id: 'product-1',
        variant_name: 'Size 40',
      });
    });
    const db = adminCtx(testEnv).firestore();
    const batch = db.batch();
    batch.update(db.collection('product_variants').doc('variant-1'), {
      quantity_available: 8,
    });
    batch.set(db.collection('seller_inventory').doc('seller-uid_variant-1'), {
      seller_id: 'seller-uid',
      seller_name: 'Seller',
      product_id: 'product-1',
      variant_id: 'variant-1',
      variant_name: 'Size 40',
      quantity_available: 12,
      active: true,
      tenant_id: 'tenant-1',
    });
    batch.set(db.collection('inventory_transactions').doc('transfer-1'), {
      type: 'transfer_out',
      seller_id: 'seller-uid',
      seller_name: 'Seller',
      product_id: 'product-1',
      variant_id: 'variant-1',
      variant_name: 'Size 40',
      quantity: 12,
      created_by: 'admin-uid',
      created_at: new Date(),
      tenant_id: 'tenant-1',
    });
    await assertSucceeds(batch.commit());
  });

  it('admin: can return seller stock when the audit row carries its tenant', async () => {
    await seedUser('admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('product_variants').doc('variant-1').set({
        tenant_id: 'tenant-1',
        quantity_available: 5,
        product_id: 'product-1',
        variant_name: 'Size 40',
      });
      await db.collection('seller_inventory').doc('seller-uid_variant-1').set({
        tenant_id: 'tenant-1',
        seller_id: 'seller-uid',
        quantity_available: 12,
      });
    });
    const db = adminCtx(testEnv).firestore();
    const batch = db.batch();
    batch.update(db.collection('seller_inventory').doc('seller-uid_variant-1'), {
      quantity_available: 0,
    });
    batch.update(db.collection('product_variants').doc('variant-1'), {
      quantity_available: 17,
    });
    batch.set(db.collection('inventory_transactions').doc('return-1'), {
      type: 'return_to_warehouse',
      seller_id: 'seller-uid',
      seller_name: 'Seller',
      product_id: 'product-1',
      variant_id: 'variant-1',
      variant_name: 'Size 40',
      quantity: 12,
      created_by: 'admin-uid',
      created_at: new Date(),
      tenant_id: 'tenant-1',
    });
    await assertSucceeds(batch.commit());
  });

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

  it('legacy workspace admin can read own tenant policy but cannot edit it', async () => {
    await seedUser('admin-uid', 'admin');
    await seedWorkspace('tenant-1');
    const db = adminCtx(testEnv).firestore();
    await assertSucceeds(db.collection('tenants').doc('tenant-1').get());
    await assertFails(
      db.collection('tenants').doc('tenant-1').update({
        max_devices_allowed: 999,
      }),
    );
  });

  it('selected super-admin can archive and restore a workspace', async () => {
    await seedWorkspace('tenant-1');
    await seedUser('platform-lifecycle-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Workspace lifecycle maintenance',
      active_workspace_selected_at: new Date(),
    });
    const tenantRef = testEnv.authenticatedContext('platform-lifecycle-uid')
      .firestore().collection('tenants').doc('tenant-1');

    await assertSucceeds(
      tenantRef.update({
        active: false,
        archived_at: firebase.firestore.FieldValue.serverTimestamp(),
        archived_by: 'platform-lifecycle-uid',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertSucceeds(
      tenantRef.update({
        active: true,
        archived_at: firebase.firestore.FieldValue.delete(),
        archived_by: firebase.firestore.FieldValue.delete(),
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('unselected super-admin cannot change workspace lifecycle', async () => {
    await seedWorkspace('tenant-1');
    await seedUser('platform-unselected-lifecycle-uid', 'super_admin');
    const tenantRef = testEnv.authenticatedContext(
      'platform-unselected-lifecycle-uid',
    ).firestore().collection('tenants').doc('tenant-1');
    await assertFails(
      tenantRef.update({
        active: false,
        archived_at: firebase.firestore.FieldValue.serverTimestamp(),
        archived_by: 'platform-unselected-lifecycle-uid',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('archive revokes tenant users and access records, then restores prior activity', async () => {
    await seedWorkspace('tenant-1');
    await seedUser('seller-uid', 'seller');
    await seedUser('platform-archive-flow-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Archive workspace lifecycle',
      active_workspace_selected_at: new Date(),
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('products').doc('archive-flow-product').set({
        name: 'Archive flow product',
        tenant_id: 'tenant-1',
      });
      await db.collection('users').doc('seller-uid')
        .collection('device_registrations').doc('slot_0').set({
          user_id: 'seller-uid',
          tenant_id: 'tenant-1',
          slot_id: 'slot_0',
          slot_number: 0,
          device_id: 'installation-0',
          status: 'active',
        });
      await db.collection('users').doc('seller-uid')
        .collection('sessions').doc('slot_0').set({
          user_id: 'seller-uid',
          tenant_id: 'tenant-1',
          slot_id: 'slot_0',
          slot_number: 0,
          session_id: 'archive-session-0',
          device_slot_id: 'slot_0',
          device_id: 'installation-0',
          status: 'active',
          expires_at: new Date(Date.now() + 60 * 60 * 1000),
        });
    });

    const db = testEnv.authenticatedContext('platform-archive-flow-uid')
      .firestore();
    const tenantRef = db.collection('tenants').doc('tenant-1');
    const sellerRef = db.collection('users').doc('seller-uid');
    const deviceRef = sellerRef.collection('device_registrations').doc('slot_0');
    const sessionRef = sellerRef.collection('sessions').doc('slot_0');
    const archiveBatch = db.batch();
    archiveBatch.update(tenantRef, {
      active: false,
      archived_at: firebase.firestore.FieldValue.serverTimestamp(),
      archived_by: 'platform-archive-flow-uid',
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    archiveBatch.update(sellerRef, {
      active: false,
      workspace_was_active: true,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    archiveBatch.update(deviceRef, {
      status: 'revoked',
      revoked_at: firebase.firestore.FieldValue.serverTimestamp(),
      revoked_by: 'platform-archive-flow-uid',
    });
    archiveBatch.update(sessionRef, {
      status: 'revoked',
      revoked_at: firebase.firestore.FieldValue.serverTimestamp(),
      termination_reason: 'workspace_archived',
      terminated_by: 'platform-archive-flow-uid',
    });
    await assertSucceeds(archiveBatch.commit());
    await assertFails(
      sellerCtx(testEnv).firestore()
        .collection('products')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
    );

    const restoreBatch = db.batch();
    restoreBatch.update(tenantRef, {
      active: true,
      archived_at: firebase.firestore.FieldValue.delete(),
      archived_by: firebase.firestore.FieldValue.delete(),
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    restoreBatch.update(sellerRef, {
      active: true,
      workspace_was_active: firebase.firestore.FieldValue.delete(),
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(restoreBatch.commit());
    await assertSucceeds(
      sellerCtx(testEnv).firestore()
        .collection('products')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
    );
  });

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

  it('super-admin can atomically create a workspace and its settings', async () => {
    await seedUser('platform-create-workspace-uid', 'super_admin');
    const db = testEnv.authenticatedContext('platform-create-workspace-uid').firestore();
    const batch = db.batch();
    const tenantRef = db.collection('tenants').doc('tenant-new');
    batch.set(tenantRef, {
      name: 'New Workspace',
      slug: 'tenant-new',
      tenant_id: 'tenant-new',
      created_by: 'platform-create-workspace-uid',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
      active: true,
    });
    batch.set(db.collection('settings').doc('tenant-new'), {
      tenant_id: 'tenant-new',
      company_name: 'New Workspace',
      currency: 'SAR',
      pairs_per_carton: 12,
      last_invoice_number: 0,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('workspace selection rejects the client payload extra access-log id', async () => {
    await seedWorkspace('tenant-a');
    await seedUser('platform-select-payload-uid', 'super_admin');
    const db = testEnv.authenticatedContext('platform-select-payload-uid').firestore();
    const batch = db.batch();
    const logRef = db.collection('platform_access_logs').doc('start-log');
    batch.update(db.collection('users').doc('platform-select-payload-uid'), {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: firebase.firestore.FieldValue.serverTimestamp(),
      active_workspace_access_log_id: logRef.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(logRef, {
      actor_user_id: 'platform-select-payload-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_started',
      reason: 'Support ticket investigation',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertFails(batch.commit());

    const allowedBatch = db.batch();
    const allowedLogRef = db.collection('platform_access_logs').doc('start-log-allowed');
    allowedBatch.update(db.collection('users').doc('platform-select-payload-uid'), {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: firebase.firestore.FieldValue.serverTimestamp(),
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    allowedBatch.set(allowedLogRef, {
      actor_user_id: 'platform-select-payload-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_started',
      reason: 'Support ticket investigation',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(allowedBatch.commit());
  });

  it('workspace exit rejects the client payload extra access-log fields', async () => {
    await seedWorkspace('tenant-a');
    await seedUser('platform-exit-payload-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: new Date(),
      active_workspace_access_log_id: 'start-log',
    });
    const db = testEnv.authenticatedContext('platform-exit-payload-uid').firestore();
    const batch = db.batch();
    const logRef = db.collection('platform_access_logs').doc('end-log');
    batch.update(db.collection('users').doc('platform-exit-payload-uid'), {
      active_workspace_id: firebase.firestore.FieldValue.delete(),
      active_workspace_reason: firebase.firestore.FieldValue.delete(),
      active_workspace_selected_at: firebase.firestore.FieldValue.delete(),
      active_workspace_access_log_id: firebase.firestore.FieldValue.delete(),
      last_workspace_access_log_id: logRef.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(logRef, {
      actor_user_id: 'platform-exit-payload-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_ended',
      reason: 'Support ticket investigation',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertFails(batch.commit());

    const allowedBatch = db.batch();
    const allowedLogRef = db.collection('platform_access_logs').doc('end-log-allowed');
    allowedBatch.update(db.collection('users').doc('platform-exit-payload-uid'), {
      active_workspace_id: firebase.firestore.FieldValue.delete(),
      active_workspace_reason: firebase.firestore.FieldValue.delete(),
      active_workspace_selected_at: firebase.firestore.FieldValue.delete(),
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    allowedBatch.set(allowedLogRef, {
      actor_user_id: 'platform-exit-payload-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_ended',
      reason: 'Support ticket investigation',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(allowedBatch.commit());
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

  it('expired workspace selection cannot read tenant business data', async () => {
    await seedWorkspace('tenant-a');
    await seedBusinessCollections(['tenant-a']);
    await seedUser('platform-expired-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: new Date(Date.now() - 9 * 60 * 60 * 1000),
    });
    await assertFails(
      testEnv.authenticatedContext('platform-expired-uid')
        .firestore()
        .collection('products')
        .where('tenant_id', '==', 'tenant-a')
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
