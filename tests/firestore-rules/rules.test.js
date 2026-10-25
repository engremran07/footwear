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
function tenantAdminCtx(env) {
  return env.authenticatedContext('tenant-admin-uid', {
    email: 'tenant-admin@test.com',
  });
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
    const db = ctx.firestore();
    const tenantId = extra.tenant_id ?? 'tenant-1';
    if (typeof tenantId === 'string' && tenantId !== '' && tenantId !== '__global__') {
      const tenantRef = db.collection('tenants').doc(tenantId);
      const tenant = await tenantRef.get();
      if (!tenant.exists) {
        await tenantRef.set({
          tenant_id: tenantId,
          active: true,
          plan: 'free',
          active_user_count: 0,
          max_active_users: 10,
          seat_count_revision: 0,
        });
      }
    }
    await db.collection('users').doc(uid).set({
      role,
      active,
      display_name: 'Test User',
      email: `${uid}@test.com`,
      tenant_id: 'tenant-1',
      assigned_route_ids: ['route-1'],
      ...extra,
    });
    if (
      typeof tenantId === 'string' &&
      tenantId !== '' &&
      tenantId !== '__global__' &&
      active &&
      !/^\s*super_admin\s*$/i.test(role)
    ) {
      const tenantRef = db.collection('tenants').doc(tenantId);
      const tenant = await tenantRef.get();
      if (Number.isInteger(tenant.data()?.active_user_count)) {
        await tenantRef.update({
          active_user_count: tenant.data().active_user_count + 1,
        });
      }
    }
  });
}

async function seedTenant({
  tenantId = 'tenant-1',
  ownerUserId = 'tenant-admin-uid',
  includeTenantId = true,
  activeUserCount,
  initializeSeatCount = true,
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    let count = activeUserCount;
    if (count == null) {
      const users = await db
        .collection('users')
        .where('tenant_id', '==', tenantId)
        .where('active', '==', true)
        .get();
      count = users.docs.filter(
        (user) => !/^\s*super_admin\s*$/i.test(user.data().role ?? ''),
      ).length;
    }
    await db.collection('tenants').doc(tenantId).set({
      ...(includeTenantId ? { tenant_id: tenantId } : {}),
      owner_user_id: ownerUserId,
      active: true,
      ...(initializeSeatCount
        ? {
            plan: 'free',
            active_user_count: count,
            max_active_users: 10,
            seat_count_revision: 0,
          }
        : {}),
    });
  });
}

function applySeatChange(batch, db, tenantId, userId, count, revision, kind) {
  batch.update(db.collection('tenants').doc(tenantId), {
    active_user_count: count,
    seat_count_revision: revision + 1,
    seat_change_user_id: userId,
    seat_change_kind: kind,
    updated_at: firebase.firestore.FieldValue.serverTimestamp(),
  });
}

function createUserWithSeat(db, userId, {
  tenantId = 'tenant-1',
  role = 'seller',
  createdBy = 'admin-uid',
} = {}) {
  const batch = db.batch();
  const userRef = db.collection('users').doc(userId);
  batch.set(userRef, {
    role,
    active: true,
    display_name: 'New Seller',
    email: `${userId}@test.com`,
    tenant_id: tenantId,
    created_by: createdBy,
    assigned_route_ids: ['route-1'],
  });
  return db
    .collection('tenants')
    .doc(tenantId)
    .get()
    .then((snapshot) => {
      const tenant = snapshot.data();
      applySeatChange(
        batch,
        db,
        tenantId,
        userId,
        tenant.active_user_count + 1,
        tenant.seat_count_revision ?? 0,
        'add',
      );
      return batch.commit();
    });
}

async function setUserActiveWithSeat(db, tenantId, userId, active) {
    const tenantRef = db.collection('tenants').doc(tenantId);
    const userRef = db.collection('users').doc(userId);
    const tenantSnapshot = await tenantRef.get();
    const tenant = tenantSnapshot.data();
    const batch = db.batch();
    batch.update(userRef, {
      active,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    applySeatChange(
      batch,
      db,
      tenantId,
      userId,
      tenant.active_user_count + (active ? 1 : -1),
      tenant.seat_count_revision ?? 0,
      active ? 'add' : 'remove',
    );
    return batch.commit();
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
      createUserWithSeat(
        adminCtx(testEnv).firestore(),
        'new-uid',
      ),
    );
  });

  it('admin: cannot create an active user without the atomic seat increment', async () => {
    await seedUser('admin-uid', 'admin');
    await assertFails(
      adminCtx(testEnv).firestore().collection('users').doc('orphan-uid').set({
        role: 'seller',
        active: true,
        display_name: 'Uncounted Seller',
        email: 'orphan@test.com',
        tenant_id: 'tenant-1',
        created_by: 'admin-uid',
        assigned_route_ids: ['route-1'],
      }),
    );
  });

  it('admin: enforces the ten-seat limit and allows the tenth active account', async () => {
    await seedUser('admin-uid', 'admin');
    for (let index = 0; index < 8; index += 1) {
      await seedUser(`seller-${index}`, 'seller');
    }
    const db = adminCtx(testEnv).firestore();
    await assertSucceeds(createUserWithSeat(db, 'tenth-user'));
    await assertFails(createUserWithSeat(db, 'eleventh-user'));
  });

  it('admin: cannot change a seat counter without its matching user transition', async () => {
    await seedUser('admin-uid', 'admin');
    const db = adminCtx(testEnv).firestore();
    await assertFails(
      db.collection('tenants').doc('tenant-1').update({
        active_user_count: 2,
        seat_count_revision: 1,
        seat_change_user_id: 'missing-user',
        seat_change_kind: 'add',
        updated_at: new Date(),
      }),
    );
  });

  it('admin: must decrement active seats atomically when deactivating a seller', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    const db = adminCtx(testEnv).firestore();
    await assertSucceeds(
      setUserActiveWithSeat(db, 'tenant-1', 'seller-uid', false),
    );
    const tenant = await db.collection('tenants').doc('tenant-1').get();
    assert.strictEqual(tenant.data().active_user_count, 1);
  });

  it('admin: cannot reactivate an account when the workspace is at capacity', async () => {
    await seedUser('admin-uid', 'admin');
    for (let index = 0; index < 9; index += 1) {
      await seedUser(`seller-${index}`, 'seller');
    }
    await seedUser('inactive-seller', 'seller', false);
    const db = adminCtx(testEnv).firestore();
    await assertFails(
      setUserActiveWithSeat(db, 'tenant-1', 'inactive-seller', true),
    );
  });

  it('grandfathered over-cap workspaces deny additions but allow a seat release', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    await seedUser('inactive-seller', 'seller', false);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('tenants').doc('tenant-1').update({
        active_user_count: 11,
      });
    });
    const db = adminCtx(testEnv).firestore();
    await assertFails(createUserWithSeat(db, 'blocked-new-user'));
    await assertSucceeds(
      setUserActiveWithSeat(db, 'tenant-1', 'seller-uid', false),
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

  it('workspace admin can create and update routes in their tenant', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const route = db.collection('routes').doc('r-workspace-admin');

    await assertSucceeds(route.set({
      name: 'Workspace Route',
      route_number: 2,
      total_shops: 0,
      active: true,
      tenant_id: 'tenant-1',
    }));
    await assertSucceeds(route.update({ name: 'Updated Workspace Route' }));
  });

  it('workspace admin cannot create a route in another tenant', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await assertFails(
      testEnv.authenticatedContext('tenant-admin-uid')
        .firestore().collection('routes').doc('r-foreign').set({
          name: 'Foreign Route',
          route_number: 2,
          total_shops: 0,
          active: true,
          tenant_id: 'tenant-2',
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
  it('tenant-scoped shop ID lookups exclude other workspaces', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedTenant({ tenantId: 'tenant-2', ownerUserId: 'other-admin' });
    await seedShop('shop-active', { active: true });
    await seedShop('shop-inactive', { active: false });
    await seedShop('shop-other-tenant', {
      tenant_id: 'tenant-2',
      active: true,
    });

    const db = tenantAdminCtx(testEnv).firestore();
    const result = await assertSucceeds(
      db.collection('customers')
        .where('tenant_id', '==', 'tenant-1')
        .where(firebase.firestore.FieldPath.documentId(), 'in', [
          'shop-active',
          'shop-inactive',
        ])
        .get(),
    );

    assert.deepStrictEqual(
      result.docs.map((doc) => doc.id).sort(),
      ['shop-active', 'shop-inactive'],
    );

    await assertFails(
      db.collection('customers')
        .where('tenant_id', '==', 'tenant-2')
        .where(firebase.firestore.FieldPath.documentId(), 'in', [
          'shop-other-tenant',
        ])
        .get(),
    );
  });

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

  it('seller can atomically create a shop and reconcile its route count', async () => {
    await seedUser('seller-uid', 'seller', true, {
      assigned_route_ids: ['route-1'],
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('routes').doc('route-1').set({
        name: 'Assigned Route',
        route_number: 1,
        total_shops: 0,
        assigned_seller_ids: ['seller-uid'],
        tenant_id: 'tenant-1',
        active: true,
      });
    });
    const db = sellerCtx(testEnv).firestore();
    const shopRef = db.collection('customers').doc('shop-counted');
    const batch = db.batch();
    batch.set(shopRef, {
      name: 'Counted Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      balance: 0,
      active: true,
    });
    batch.update(db.collection('routes').doc('route-1'), {
      total_shops: 1,
      last_shop_created_id: shopRef.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
  });

  it('seller cannot change a route count without creating its linked shop', async () => {
    await seedUser('seller-uid', 'seller', true, {
      assigned_route_ids: ['route-1'],
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('routes').doc('route-1').set({
        name: 'Assigned Route',
        route_number: 1,
        total_shops: 0,
        assigned_seller_ids: ['seller-uid'],
        tenant_id: 'tenant-1',
        active: true,
      });
    });
    await assertFails(
      sellerCtx(testEnv).firestore().collection('routes').doc('route-1').update({
        total_shops: 1,
        last_shop_created_id: 'missing-shop',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('workspace admin can create and update shops in their tenant', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('routes').doc('route-1').set({
        name: 'Workspace Route',
        route_number: 1,
        total_shops: 0,
        tenant_id: 'tenant-1',
        active: true,
      });
    });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const shop = db.collection('customers').doc('shop-workspace-admin');
    const batch = db.batch();

    batch.set(shop, {
      name: 'Workspace Shop',
      route_id: 'route-1',
      route_number: 1,
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      balance: 0,
      active: true,
    });
    batch.update(db.collection('routes').doc('route-1'), {
      total_shops: 1,
      last_shop_created_id: shop.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
    await assertSucceeds(shop.update({ name: 'Updated Workspace Shop' }));
  });

  it('workspace admin cannot create a shop with an opening balance', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await assertFails(
      testEnv.authenticatedContext('tenant-admin-uid')
        .firestore()
        .collection('customers')
        .doc('shop-opening-balance')
        .set({
          name: 'Shop with opening balance',
          route_id: 'route-1',
          tenant_id: 'tenant-1',
          balance: 500,
          active: true,
        }),
    );
  });

  it('workspace admin cannot create or update shops in another tenant', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const foreignShop = db.collection('customers').doc('shop-foreign');

    await assertFails(foreignShop.set({
      name: 'Foreign Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-2',
      balance: 0,
      active: true,
    }));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('customers').doc('shop-foreign').set({
        name: 'Seeded Foreign Shop',
        route_id: 'route-1',
        tenant_id: 'tenant-2',
        balance: 0,
        active: true,
      });
    });
    await assertFails(foreignShop.update({ name: 'Changed Foreign Shop' }));
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

  it('workspace backup reads settings by the tenant document ID', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedSettings({ company_name: 'Workspace One' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertFails(
      db.collection('settings').where('tenant_id', '==', 'tenant-1').get(),
    );
    const settings = await assertSucceeds(
      db.collection('settings').doc('tenant-1').get(),
    );
    assert.strictEqual(settings.data().company_name, 'Workspace One');
  });
});

describe('backup read scopes', () => {
  it('workspace admin can query every tenant-owned backup collection', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedSettings();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const collection of [
        'routes',
        'customers',
        'products',
        'product_variants',
        'seller_inventory',
        'inventory_transactions',
        'transactions',
        'invoices',
      ]) {
        await db.collection(collection).doc(`backup-${collection}`).set({
          tenant_id: 'tenant-1',
          route_id: 'route-1',
          seller_id: 'tenant-admin-uid',
        });
      }
    });

    const db = tenantAdminCtx(testEnv).firestore();
    for (const collection of [
      'routes',
      'customers',
      'products',
      'product_variants',
      'seller_inventory',
      'inventory_transactions',
      'transactions',
      'invoices',
    ]) {
      await assertSucceeds(
        db.collection(collection)
          .where('tenant_id', '==', 'tenant-1')
          .orderBy(firebase.firestore.FieldPath.documentId())
          .limit(500)
          .get(),
      );
    }
  });

  it('seller can query only assigned-route backup data', async () => {
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('routes').doc('route-1').set({
        tenant_id: 'tenant-1',
        assigned_seller_ids: ['seller-uid'],
      });
      await db.collection('routes').doc('route-2').set({
        tenant_id: 'tenant-1',
        assigned_seller_ids: ['other-seller'],
      });
      for (const collection of ['customers', 'transactions', 'invoices']) {
        await db.collection(collection).doc(`backup-${collection}`).set({
          tenant_id: 'tenant-1',
          route_id: 'route-1',
        });
        await db.collection(collection).doc(`foreign-${collection}`).set({
          tenant_id: 'tenant-1',
          route_id: 'route-2',
        });
      }
      for (const collection of ['seller_inventory', 'inventory_transactions']) {
        await db.collection(collection).doc(`backup-${collection}`).set({
          tenant_id: 'tenant-1',
          seller_id: 'seller-uid',
        });
        await db.collection(collection).doc(`foreign-${collection}`).set({
          tenant_id: 'tenant-1',
          seller_id: 'other-seller',
        });
      }
    });

    const db = sellerCtx(testEnv).firestore();
    await assertSucceeds(
      db.collection('routes')
        .where('tenant_id', '==', 'tenant-1')
        .where('assigned_seller_ids', 'array-contains', 'seller-uid')
        .orderBy(firebase.firestore.FieldPath.documentId())
        .limit(500)
        .get(),
    );
    for (const collection of ['customers', 'transactions', 'invoices']) {
      await assertSucceeds(
        db.collection(collection)
          .where('tenant_id', '==', 'tenant-1')
          .where('route_id', 'in', ['route-1'])
          .orderBy(firebase.firestore.FieldPath.documentId())
          .limit(500)
          .get(),
      );
      await assertFails(
        db.collection(collection)
          .where('tenant_id', '==', 'tenant-1')
          .where('route_id', 'in', ['route-2'])
          .get(),
      );
    }
    for (const collection of ['seller_inventory', 'inventory_transactions']) {
      await assertSucceeds(
        db.collection(collection)
          .where('tenant_id', '==', 'tenant-1')
          .where('seller_id', '==', 'seller-uid')
          .orderBy(firebase.firestore.FieldPath.documentId())
          .limit(500)
          .get(),
      );
      await assertFails(
        db.collection(collection)
          .where('tenant_id', '==', 'tenant-1')
          .where('seller_id', '==', 'other-seller')
          .get(),
      );
    }
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
    await seedSettings({
      company_name: 'Workspace Name',
      invoice_header: {
        name_en: 'Workspace Name',
        visible_fields: [],
        document_language_pair: 'english_urdu',
      },
      logo_base64: 'workspace-logo',
    });
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
      invoice_header_snapshot: {
        name_en: 'Workspace Name',
        visible_fields: [],
        document_language_pair: 'english_urdu',
        company_name: 'Workspace Name',
        logo_base64: 'workspace-logo',
      },
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

  it('tenant admin can atomically create a partial sale with linked ledger rows', async () => {
    await seedTenant();
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 20 });
    await seedSettings({ allow_non_stock_invoices: true });
    const db = tenantAdminCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('tenant-admin-partial-sale');
    const saleRef = db.collection('transactions').doc('tenant-admin-sale-out');
    const paymentRef = db.collection('transactions').doc('tenant-admin-sale-in');
    const batch = db.batch();
    batch.set(invoiceRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      invoice_number: 'INV-2026-TENANT-ADMIN',
      sale_transaction_id: saleRef.id,
      payment_transaction_id: paymentRef.id,
      type: 'sale',
      fulfillment_mode: 'non_stock',
      seller_inventory_deductions: {},
      shop_id: 'shop-1',
      route_id: 'route-1',
      seller_id: 'tenant-admin-uid',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 100 }],
      subtotal: 100,
      discount: 0,
      total: 100,
      amount_received: 25,
    });
    batch.set(saleRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'cash_out',
      amount: 100,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-TENANT-ADMIN',
    });
    batch.set(paymentRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'cash_in',
      amount: 25,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-TENANT-ADMIN',
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

  it('tenant admin can create a linked cash receipt and advance its sequence', async () => {
    await seedTenant();
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 100 });
    await seedSettings();
    const db = tenantAdminCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('tenant-admin-receipt');
    const transactionRef = db.collection('transactions')
      .doc('tenant-admin-receipt-tx');
    const batch = db.batch();
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_cash_receipt_number: 1,
    });
    batch.set(invoiceRef, {
      created_by: 'tenant-admin-uid',
      type: 'cash_receipt',
      fulfillment_mode: 'none',
      cash_receipt_transaction_id: transactionRef.id,
      cash_receipt_sequence: 1,
      invoice_number: 'REC-2026-0001',
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'tenant-admin-uid',
      items: [],
      subtotal: 0,
      discount: 0,
      total: 25,
      amount_received: 25,
      status: 'paid',
    });
    batch.set(transactionRef, {
      created_by: 'tenant-admin-uid',
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

  it('tenant admin can create a linked credit note and return transaction', async () => {
    await seedTenant();
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 100 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('tenant-admin-original').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        credit_note_total: 0,
      });
    });
    const db = tenantAdminCtx(testEnv).firestore();
    const batch = db.batch();
    const originalRef = db.collection('invoices').doc('tenant-admin-original');
    const creditRef = db.collection('invoices').doc('tenant-admin-credit');
    const returnRef = db.collection('transactions').doc('tenant-admin-return');
    batch.update(originalRef, { credit_note_total: 40 });
    batch.set(creditRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'credit_note',
      return_transaction_id: returnRef.id,
      linked_invoice_id: originalRef.id,
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
      created_by: 'tenant-admin-uid',
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

  it('tenant admin can void a partial sale with its linked refund rows', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 75 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('tenant-admin-void-sale').set({
        tenant_id: 'tenant-1',
        created_by: 'seller-uid',
        type: 'sale',
        status: 'partial',
        invoice_number: 'INV-2026-TENANT-VOID',
        shop_id: 'shop-1',
        route_id: 'route-1',
        total: 100,
        amount_received: 25,
        outstanding_amount: 75,
      });
    });

    const db = tenantAdminCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('tenant-admin-void-sale');
    const reversalRef = db.collection('transactions')
      .doc('tenant-admin-void-return');
    const refundRef = db.collection('transactions')
      .doc('tenant-admin-void-refund');
    const batch = db.batch();
    batch.update(invoiceRef, {
      status: 'void',
      void_by: 'tenant-admin-uid',
      void_at: new Date(),
      updated_at: new Date(),
    });
    batch.set(reversalRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'return',
      amount: 100,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: invoiceRef.id,
    });
    batch.set(refundRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
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
    await seedSettings({
      company_name: 'Workspace Name',
      invoice_header: {
        name_en: 'Workspace Name',
        visible_fields: [],
        document_language_pair: 'english_arabic',
      },
      logo_base64: 'workspace-logo',
    });
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
      invoice_header_snapshot: {
        name_en: 'Workspace Name',
        visible_fields: [],
        document_language_pair: 'english_arabic',
        company_name: 'Workspace Name',
        logo_base64: 'workspace-logo',
      },
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

  it('seller: cannot snapshot a financial-document language pair not set by the workspace', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    await seedSettings({
      company_name: 'Workspace Name',
      invoice_header: {
        name_en: 'Workspace Name',
        visible_fields: [],
        document_language_pair: 'english_arabic',
      },
      logo_base64: 'workspace-logo',
    });
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('receipt-wrong-pair');
    const transactionRef = db.collection('transactions').doc('receipt-tx-wrong-pair');
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
      invoice_header_snapshot: {
        name_en: 'Workspace Name',
        visible_fields: [],
        document_language_pair: 'english_urdu',
        company_name: 'Workspace Name',
        logo_base64: 'workspace-logo',
      },
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

  it('selected super-admin can delete scoped data but not the workspace root', async () => {
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
      const deletion = db.collection(collection).doc(docId).delete();
      if (
        collection === 'transactions' ||
        collection === 'tenants' ||
        collection === 'users'
      ) {
        await assertFails(deletion);
      } else {
        await assertSucceeds(deletion);
      }
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
    await seedShop('shop-1', {
      balance: -100,
      last_transaction_id: 'tx-admin-edit-history',
      last_transaction_type: 'cash_in',
      last_transaction_amount: 100,
      last_transaction_at: createdAt,
    });
    await seedTransaction('tx-admin-edit-history', {
      shop_id: 'shop-1',
      created_at: createdAt,
      description: 'Original entry',
    });
    const db = adminCtx(testEnv).firestore();
    const transaction = db.collection('transactions').doc('tx-admin-edit-history');
    const batch = db.batch();
    batch.update(transaction, {
      amount: 120,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      edit_history: [{
        previous_amount: 100,
        previous_type: 'cash_in',
        previous_created_at: createdAt,
        previous_description: 'Original entry',
        changed_by: 'admin-uid',
        reason: 'Receipt amount correction',
        changed_at: new Date(),
      }],
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: -120,
      last_balance_correction_transaction_id: transaction.id,
      last_transaction_amount: 120,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  it('admin cannot correct a transaction without its atomic shop balance update', async () => {
    await seedUser('admin-uid', 'admin');
    const createdAt = new Date('2026-01-01T00:00:00.000Z');
    await seedShop('shop-1', { balance: -100 });
    await seedTransaction('tx-admin-edit-unlinked', {
      shop_id: 'shop-1',
      created_at: createdAt,
    });
    await assertFails(
      adminCtx(testEnv).firestore()
        .collection('transactions')
        .doc('tx-admin-edit-unlinked')
        .update({
          amount: 120,
          updated_at: firebase.firestore.FieldValue.serverTimestamp(),
          edit_history: [{
            previous_amount: 100,
            previous_type: 'cash_in',
            previous_created_at: createdAt,
            previous_description: 'seed',
            changed_by: 'admin-uid',
            reason: 'Receipt amount correction',
            changed_at: new Date(),
          }],
        }),
    );
  });

  it('workspace admin can correct its tenant ledger and shop balance atomically', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', {
      balance: -100,
      last_transaction_id: 'tx-workspace-edit',
      last_transaction_type: 'cash_in',
      last_transaction_amount: 100,
      last_transaction_at: new Date('2026-01-01T00:00:00.000Z'),
    });
    await seedTransaction('tx-workspace-edit', {
      created_by: 'seller-uid',
      shop_id: 'shop-1',
      tenant_id: 'tenant-1',
      type: 'cash_in',
      amount: 100,
      created_at: new Date('2026-01-01T00:00:00.000Z'),
      description: 'Original receipt',
    });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const transaction = db.collection('transactions').doc('tx-workspace-edit');
    const batch = db.batch();

    batch.update(transaction, {
      amount: 120,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      edit_history: [{
        previous_amount: 100,
        previous_type: 'cash_in',
        previous_created_at: new Date('2026-01-01T00:00:00.000Z'),
        previous_description: 'Original receipt',
        changed_by: 'tenant-admin-uid',
        reason: 'Correct recorded receipt',
        changed_at: new Date(),
      }],
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: -120,
      last_balance_correction_transaction_id: transaction.id,
      last_transaction_at: new Date('2026-01-01T00:00:00.000Z'),
      last_transaction_type: 'cash_in',
      last_transaction_amount: 120,
      last_transaction_id: transaction.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
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

  it('workspace admin can create and update tenant ledger rows', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('customers').doc('shop-1').set({
        name: 'Workspace Shop',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        balance: 0,
      });
    });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const transaction = db.collection('transactions').doc('tx-workspace-admin');
    const batch = db.batch();

    batch.set(transaction, {
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      amount: 25,
      type: 'cash_in',
      description: 'Workspace ledger row',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: -25,
      last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_type: 'cash_in',
      last_transaction_amount: 25,
      last_transaction_id: transaction.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
    await assertSucceeds(transaction.update({
      description: 'Updated workspace ledger row',
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    }));
  });

  it('workspace admin can atomically write off bad debt with a linked ledger row', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 500, bad_debt: false });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const transaction = db.collection('transactions').doc('write-off-tx');
    const batch = db.batch();

    batch.set(transaction, {
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'write_off',
      amount: 500,
      description: 'Bad debt write-off',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      bad_debt: true,
      bad_debt_amount: 500,
      bad_debt_date: firebase.firestore.FieldValue.serverTimestamp(),
      balance: 0,
      last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_type: 'write_off',
      last_transaction_amount: 500,
      last_transaction_id: transaction.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
  });

  it('workspace admin cannot write off more than the exact shop balance', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 500, bad_debt: false });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const transaction = db.collection('transactions').doc('write-off-overstated');
    const batch = db.batch();

    batch.set(transaction, {
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'write_off',
      amount: 600,
      description: 'Bad debt write-off',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      bad_debt: true,
      bad_debt_amount: 600,
      balance: 0,
      last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_type: 'write_off',
      last_transaction_amount: 600,
      last_transaction_id: transaction.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertFails(batch.commit());
  });

  it('workspace admin can recover bad debt with an atomic linked cash-out row', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', {
      balance: 0,
      bad_debt: true,
      bad_debt_amount: 500,
    });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const transaction = db.collection('transactions').doc('bad-debt-recovery');
    const batch = db.batch();

    batch.set(transaction, {
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'cash_out',
      amount: 500,
      description: 'Bad debt recovered',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      bad_debt: false,
      bad_debt_amount: 0,
      bad_debt_date: null,
      balance: 500,
      last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 500,
      last_transaction_id: transaction.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
  });

  it('workspace admin cannot create a standalone return or payment row', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 100 });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();

    for (const type of ['return', 'payment']) {
      const transaction = db.collection('transactions').doc(`standalone-${type}`);
      const batch = db.batch();
      batch.set(transaction, {
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        created_by: 'tenant-admin-uid',
        type,
        amount: 25,
        description: 'Standalone non-cash row',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
      });
      batch.update(db.collection('customers').doc('shop-1'), {
        balance: 75,
        last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
        last_transaction_type: type,
        last_transaction_amount: 25,
        last_transaction_id: transaction.id,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      });

      await assertFails(batch.commit());
    }
  });

  it('workspace admin cannot create an orphan or mismatched ledger row', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', { balance: 0 });
    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const transactionData = {
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      amount: 25,
      type: 'cash_in',
      description: 'Unlinked workspace ledger row',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    };

    await assertFails(
      db.collection('transactions').doc('tx-no-shop-update').set(transactionData),
    );

    const batch = db.batch();
    batch.set(
      db.collection('transactions').doc('tx-mismatched-shop-update'),
      transactionData,
    );
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: -24,
      last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_type: 'cash_in',
      last_transaction_amount: 25,
      last_transaction_id: 'tx-mismatched-shop-update',
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('seller cannot create a ledger row without its atomic shop balance update', async () => {
    await seedUser('seller-uid', 'seller', true, {
      assigned_route_ids: ['route-1'],
    });
    await seedShop('shop-1', { balance: 0 });
    const db = sellerCtx(testEnv).firestore();
    await assertFails(
      db.collection('transactions').doc('tx-seller-orphan').set({
        shop_id: 'shop-1',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        created_by: 'seller-uid',
        amount: 25,
        type: 'cash_in',
      }),
    );
  });

  it('seller can query assigned-shop transactions in created-at order', async () => {
    await seedUser('seller-uid', 'seller', true, {
      assigned_route_ids: ['route-1'],
    });
    await seedShop('shop-1');
    await seedTransaction('tx-shop-read', {
      type: 'cash_in',
      created_at: new Date(),
    });

    const transactions = await sellerCtx(testEnv).firestore()
      .collection('transactions')
      .where('tenant_id', '==', 'tenant-1')
      .where('shop_id', '==', 'shop-1')
      .orderBy('created_at', 'desc')
      .get();

    assert.strictEqual(transactions.size, 1);
    assert.strictEqual(transactions.docs[0].id, 'tx-shop-read');
  });

  it('seller can sort transactions for assigned routes by created-at', async () => {
    await seedUser('seller-uid', 'seller', true, {
      assigned_route_ids: ['route-1'],
    });
    await seedTransaction('tx-route-old', {
      created_at: new Date('2026-10-17T08:00:00.000Z'),
    });
    await seedTransaction('tx-route-new', {
      created_at: new Date('2026-10-18T08:00:00.000Z'),
    });

    const transactions = await sellerCtx(testEnv).firestore()
      .collection('transactions')
      .where('tenant_id', '==', 'tenant-1')
      .where('route_id', 'in', ['route-1'])
      .orderBy('created_at', 'desc')
      .get();

    assert.deepStrictEqual(
      transactions.docs.map((doc) => doc.id),
      ['tx-route-new', 'tx-route-old'],
    );
  });

  it('workspace admins can sort tenant transactions by created-at', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedTransaction('tx-tenant-old', {
      created_at: new Date('2026-10-17T08:00:00.000Z'),
    });
    await seedTransaction('tx-tenant-new', {
      created_at: new Date('2026-10-18T08:00:00.000Z'),
    });

    const transactions = await testEnv.authenticatedContext('tenant-admin-uid')
      .firestore()
      .collection('transactions')
      .where('tenant_id', '==', 'tenant-1')
      .orderBy('created_at', 'desc')
      .get();

    assert.deepStrictEqual(
      transactions.docs.map((doc) => doc.id),
      ['tx-tenant-new', 'tx-tenant-old'],
    );
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

  it('selected super-admin: can soft-delete transactions with linked balance reversal', async () => {
    await seedShop('shop-1', { balance: 100 });
    await seedUser('platform-delete-tx-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Approved workspace cleanup',
      active_workspace_selected_at: new Date(),
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('transactions').doc('tx1').set({
        shop_id: 'shop-1',
        route_id: 'route-1',
        created_by: 'seller-uid',
        amount: 100,
        type: 'cash_out',
        tenant_id: 'tenant-1',
        deleted: false,
      });
    });
    const db = testEnv.authenticatedContext('platform-delete-tx-uid').firestore();
    const batch = db.batch();
    batch.update(db.collection('transactions').doc('tx1'), {
      deleted: true,
      deleted_by: 'platform-delete-tx-uid',
      deleted_at: firebase.firestore.FieldValue.serverTimestamp(),
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 0,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_balance_correction_transaction_id: 'tx1',
    });
    await assertSucceeds(
      batch.commit(),
    );
  });

  it('prevents all transaction hard deletes', async () => {
    await seedUser('platform-delete-tx-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Approved workspace cleanup',
      active_workspace_selected_at: new Date(),
    });
    await seedTransaction('tx1');
    await assertFails(
      testEnv.authenticatedContext('platform-delete-tx-uid')
        .firestore().collection('transactions').doc('tx1').delete(),
    );
  });

  it('workspace admin can soft-delete a non-invoice transaction with atomic balance reversal', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedShop('shop-1', {
      balance: 100,
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 100,
      last_transaction_id: 'tx1',
    });
    await seedTransaction('tx1', {
      type: 'cash_out',
      amount: 100,
      deleted: false,
    });

    const db = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const batch = db.batch();
    batch.update(db.collection('transactions').doc('tx1'), {
      deleted: true,
      deleted_by: 'tenant-admin-uid',
      deleted_at: firebase.firestore.FieldValue.serverTimestamp(),
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 0,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_balance_correction_transaction_id: 'tx1',
      last_transaction_at: firebase.firestore.FieldValue.delete(),
      last_transaction_type: firebase.firestore.FieldValue.delete(),
      last_transaction_amount: firebase.firestore.FieldValue.delete(),
      last_transaction_id: firebase.firestore.FieldValue.delete(),
    });

    await assertSucceeds(batch.commit());
    const shop = await db.collection('customers').doc('shop-1').get();
    assert.strictEqual('last_transaction_id' in shop.data(), false);
  });

  it('seller cannot soft-delete a transaction or reverse its balance', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    await seedTransaction('tx1', {
      type: 'cash_out',
      amount: 100,
      deleted: false,
    });

    const db = sellerCtx(testEnv).firestore();
    const batch = db.batch();
    batch.update(db.collection('transactions').doc('tx1'), {
      deleted: true,
      deleted_by: 'seller-uid',
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 0,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 100,
      last_transaction_id: 'tx1',
    });

    await assertFails(batch.commit());
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

  it('selected super-admin can select an inactive workspace to restore it', async () => {
    await seedWorkspace('tenant-1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('tenants').doc('tenant-1').update({
        active: false,
        archived_at: new Date(),
      });
    });
    await seedUser('platform-inactive-restore-uid', 'super_admin');

    const db = testEnv.authenticatedContext(
      'platform-inactive-restore-uid',
    ).firestore();
    const userRef = db.collection('users').doc('platform-inactive-restore-uid');
    const logRef = db.collection('platform_access_logs').doc('inactive-restore');
    const selection = db.batch();
    selection.update(userRef, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Restore inactive workspace',
      active_workspace_selected_at:
        firebase.firestore.FieldValue.serverTimestamp(),
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    selection.set(logRef, {
      actor_user_id: 'platform-inactive-restore-uid',
      workspace_id: 'tenant-1',
      event_type: 'workspace_access_started',
      reason: 'Restore inactive workspace',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(selection.commit());
    const tenantRef = db.collection('tenants').doc('tenant-1');
    await assertSucceeds(
      db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(tenantRef);
        assert.strictEqual(snapshot.data().active, false);
        transaction.update(tenantRef, {
          active: true,
          archived_at: firebase.firestore.FieldValue.delete(),
          archived_by: firebase.firestore.FieldValue.delete(),
          updated_at: firebase.firestore.FieldValue.serverTimestamp(),
        });
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

  it('inactive workspace blocks active members until it is restored', async () => {
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
    });

    const db = testEnv.authenticatedContext('platform-archive-flow-uid')
      .firestore();
    const tenantRef = db.collection('tenants').doc('tenant-1');
    const archiveBatch = db.batch();
    archiveBatch.update(tenantRef, {
      active: false,
      archived_at: firebase.firestore.FieldValue.serverTimestamp(),
      archived_by: 'platform-archive-flow-uid',
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(archiveBatch.commit());
    const sellerProfile = await assertSucceeds(
      sellerCtx(testEnv).firestore().collection('users').doc('seller-uid').get(),
    );
    assert.strictEqual(sellerProfile.data().active, true);
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

  it('inactive tenant denies business access while member profiles stay active', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('seller-uid', 'seller', true, {
      assigned_route_ids: ['route-1'],
    });
    await seedShop('shop-inactive-tenant');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('products').doc('inactive-tenant-product').set({
        name: 'Inactive tenant product',
        tenant_id: 'tenant-1',
      });
      await db.collection('tenants').doc('tenant-1').update({ active: false });
    });

    const adminDb = testEnv.authenticatedContext('tenant-admin-uid').firestore();
    const sellerDb = sellerCtx(testEnv).firestore();
    const profile = await adminDb.collection('users').doc('tenant-admin-uid').get();
    assert.strictEqual(profile.data().active, true);

    await assertFails(
      adminDb.collection('products').doc('inactive-tenant-product').get(),
    );
    await assertFails(
      adminDb.collection('customers').doc('shop-inactive-tenant').get(),
    );
    await assertFails(
      adminDb.collection('customers')
        .doc('shop-inactive-tenant')
        .update({ name: 'Blocked while workspace is inactive' }),
    );
    await assertFails(
      sellerDb.collection('customers').doc('shop-inactive-tenant').get(),
    );
    await assertFails(
      sellerDb.collection('products').doc('inactive-tenant-product').get(),
    );

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('tenants').doc('tenant-1').update({
        active: true,
      });
    });
    await assertSucceeds(
      adminDb.collection('products').doc('inactive-tenant-product').get(),
    );
    await assertSucceeds(
      sellerDb.collection('customers').doc('shop-inactive-tenant').get(),
    );
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
      plan: 'free',
      active_user_count: 0,
      max_active_users: 10,
      seat_count_revision: 0,
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

  it('super-admin user-list queries stay within the selected workspace', async () => {
    await seedWorkspace('tenant-a');
    await seedWorkspace('tenant-b');
    await seedUser('platform-user-read-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: new Date(),
    });
    await seedUser('tenant-a-user', 'seller', true, {
      tenant_id: 'tenant-a',
    });
    await seedUser('tenant-b-user', 'seller', true, {
      tenant_id: 'tenant-b',
    });
    const db = testEnv.authenticatedContext('platform-user-read-uid')
      .firestore();
    await assertSucceeds(
      db.collection('users').where('tenant_id', '==', 'tenant-a').get(),
    );
    await assertFails(
      db.collection('users').where('tenant_id', '==', 'tenant-b').get(),
    );
    await assertFails(
      db.collection('users')
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

describe('client transactions that read documents before creating them', () => {
  it('admin and seller can read a missing invoice only in an active workspace', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    const adminDb = adminCtx(testEnv).firestore();
    const sellerDb = sellerCtx(testEnv).firestore();

    await assertSucceeds(
      adminDb.collection('invoices').doc('new-admin-invoice').get(),
    );
    await assertSucceeds(
      sellerDb.collection('invoices').doc('new-seller-invoice').get(),
    );

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('tenants').doc('tenant-1').update({
        active: false,
      });
    });
    await assertFails(
      adminDb.collection('invoices').doc('inactive-workspace-invoice').get(),
    );
    await assertFails(
      sellerDb.collection('invoices').doc('inactive-workspace-invoice').get(),
    );
  });

  it('active sellers may probe a missing transaction id for route restore', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 0 });
    const db = sellerCtx(testEnv).firestore();
    const transactionRef = db.collection('transactions').doc('restored-transaction');
    const shopRef = db.collection('customers').doc('shop-1');
    await assertSucceeds(db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(transactionRef);
      const shop = await transaction.get(shopRef);
      assert.strictEqual(snapshot.exists, false);
      assert.ok(shop.exists);
      transaction.set(transactionRef, {
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        created_by: 'seller-uid',
        amount: 25,
        type: 'cash_in',
        description: 'Restored route transaction',
        created_at: new Date(),
        deleted: false,
      });
      transaction.update(shopRef, {
        balance: -25,
        updated_at: new Date(),
        last_transaction_at: new Date(),
        last_transaction_type: 'cash_in',
        last_transaction_amount: 25,
        last_transaction_id: transactionRef.id,
      });
    }));
  });

  it('only workspace admins may probe a missing seller inventory document', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    const adminDb = adminCtx(testEnv).firestore();
    const sellerDb = sellerCtx(testEnv).firestore();

    await assertSucceeds(
      adminDb.collection('seller_inventory').doc('seller-uid_variant-1').get(),
    );
    await assertFails(
      sellerDb.collection('seller_inventory').doc('other-seller_variant-1').get(),
    );
  });

  it('admin first-stock transfer reads and creates the missing seller inventory atomically', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('product_variants').doc('variant-1').set({
        tenant_id: 'tenant-1',
        product_id: 'product-1',
        quantity_available: 5,
        active: true,
        updated_at: new Date('2026-01-01T00:00:00.000Z'),
      });
    });
    const db = adminCtx(testEnv).firestore();
    const variantRef = db.collection('product_variants').doc('variant-1');
    const sellerInventoryRef = db
      .collection('seller_inventory')
      .doc('seller-uid_variant-1');
    const inventoryAuditRef = db.collection('inventory_transactions').doc();

    await assertSucceeds(db.runTransaction(async (transaction) => {
      const variant = await transaction.get(variantRef);
      const sellerInventory = await transaction.get(sellerInventoryRef);
      assert.ok(variant.exists);
      assert.strictEqual(sellerInventory.exists, false);
      transaction.update(variantRef, {
        quantity_available: 3,
        updated_at: new Date(),
      });
      transaction.set(sellerInventoryRef, {
        seller_id: 'seller-uid',
        seller_name: 'Test User',
        product_id: 'product-1',
        variant_id: 'variant-1',
        variant_name: 'Variant 1',
        quantity_available: 2,
        active: true,
        tenant_id: 'tenant-1',
        created_at: new Date(),
        updated_at: new Date(),
      });
      transaction.set(inventoryAuditRef, {
        type: 'transfer_out',
        seller_id: 'seller-uid',
        seller_name: 'Test User',
        product_id: 'product-1',
        variant_id: 'variant-1',
        variant_name: 'Variant 1',
        quantity: 2,
        created_by: 'admin-uid',
        created_at: new Date(),
        tenant_id: 'tenant-1',
      });
    }));
  });

  it('selected super-admin can probe a missing invoice only in the selected workspace', async () => {
    await seedTenant();
    await seedUser('platform-selected-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Support ticket verification',
      active_workspace_selected_at: new Date(),
    });
    await seedUser('platform-unselected-uid', 'super_admin');
    await seedUser('platform-expired-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Support ticket verification',
      active_workspace_selected_at: new Date(Date.now() - 9 * 60 * 60 * 1000),
    });
    const selectedDb = testEnv
      .authenticatedContext('platform-selected-uid')
      .firestore();
    const unselectedDb = testEnv
      .authenticatedContext('platform-unselected-uid')
      .firestore();
    const expiredDb = testEnv
      .authenticatedContext('platform-expired-uid')
      .firestore();

    await assertSucceeds(
      selectedDb.collection('invoices').doc('selected-missing-invoice').get(),
    );
    await assertFails(
      unselectedDb.collection('invoices').doc('unselected-missing-invoice').get(),
    );
    await assertFails(
      expiredDb.collection('invoices').doc('expired-missing-invoice').get(),
    );
  });

  it('missing-document allowances do not reveal existing invoices from another tenant', async () => {
    await seedTenant({ tenantId: 'tenant-2' });
    await seedUser('admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('foreign-existing-invoice').set({
        tenant_id: 'tenant-2',
        type: 'sale',
      });
    });

    await assertFails(
      adminCtx(testEnv).firestore()
        .collection('invoices')
        .doc('foreign-existing-invoice')
        .get(),
    );
  });

  it('super-admin can read missing settings only while creating a new workspace', async () => {
    await seedUser('platform-create-workspace-uid', 'super_admin');
    const db = testEnv
      .authenticatedContext('platform-create-workspace-uid')
      .firestore();
    await seedTenant({ tenantId: 'tenant-without-settings' });
    await assertFails(
      db.collection('settings').doc('tenant-without-settings').get(),
    );

    const tenantRef = db.collection('tenants').doc('tenant-new');
    const settingsRef = db.collection('settings').doc('tenant-new');

    await assertSucceeds(db.runTransaction(async (transaction) => {
      const tenant = await transaction.get(tenantRef);
      const settings = await transaction.get(settingsRef);
      assert.strictEqual(tenant.exists, false);
      assert.strictEqual(settings.exists, false);
      transaction.set(tenantRef, {
        name: 'New Workspace',
        slug: 'tenant-new',
        tenant_id: 'tenant-new',
        created_by: 'platform-create-workspace-uid',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
        active: true,
        plan: 'free',
        active_user_count: 0,
        max_active_users: 10,
        seat_count_revision: 0,
      });
      transaction.set(settingsRef, {
        tenant_id: 'tenant-new',
        company_name: 'New Workspace',
        currency: 'SAR',
        pairs_per_carton: 12,
        last_invoice_number: 0,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      });
    }));
  });

  async function seedSale({ role, uid, lineCount = 1 }) {
    await seedTenant();
    await seedUser(uid, role, true, { assigned_route_ids: ['route-1'] });
    await seedShop('shop-1', { balance: 0 });
    await seedSettings({
      company_name: 'Acme Footwear',
      invoice_header: { show_phone: true },
      logo_base64: null,
      last_invoice_number: 0,
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (let index = 1; index <= lineCount; index++) {
        await db.collection('seller_inventory').doc(`inventory-${index}`).set({
          seller_id: uid,
          tenant_id: 'tenant-1',
          quantity_available: 5,
        });
      }
    });
  }

  function saleTransaction(db, uid, { lineCount = 1, amountReceived = 0 } = {}) {
    const settingsRef = db.collection('settings').doc('tenant-1');
    const shopRef = db.collection('customers').doc('shop-1');
    const invoiceRef = db.collection('invoices').doc('invoice-client-shape');
    const saleRef = db.collection('transactions').doc('sale-client-shape');
    const paymentRef = db.collection('transactions').doc('payment-client-shape');
    const inventoryRefs = Array.from({ length: lineCount }, (_, index) =>
      db.collection('seller_inventory').doc(`inventory-${index + 1}`),
    );
    const total = lineCount * 100;
    const items = Array.from({ length: lineCount }, (_, index) => ({
      variant_id: `variant-${index + 1}`,
      qty: 1,
      unit_price: 100,
    }));

    return db.runTransaction(async (transaction) => {
      const settingsSnapshot = await transaction.get(settingsRef);
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const shopSnapshot = await transaction.get(shopRef);
      const inventorySnapshots = [];
      for (const inventoryRef of inventoryRefs) {
        inventorySnapshots.push(await transaction.get(inventoryRef));
      }
      assert.strictEqual(invoiceSnapshot.exists, false);
      assert.ok(settingsSnapshot.exists);
      assert.ok(shopSnapshot.exists);
      assert.ok(inventorySnapshots.every((snapshot) => snapshot.exists));

      const now = new Date();
      transaction.update(settingsRef, { last_invoice_number: 1 });
      transaction.set(invoiceRef, {
        tenant_id: 'tenant-1',
        invoice_number: 'INV-2026-0001',
        sale_transaction_id: saleRef.id,
        idempotency_key: 'client-shape-key',
        type: 'sale',
        fulfillment_mode: 'stock',
        invoice_header_snapshot: {
          show_phone: true,
          company_name: 'Acme Footwear',
        },
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        seller_id: uid,
        seller_name: 'Test User',
        items,
        subtotal: total,
        discount: 0,
        total,
        amount_received: amountReceived,
        ...(amountReceived > 0 ? { payment_transaction_id: paymentRef.id } : {}),
        outstanding_amount: total - amountReceived,
        currency: 'SAR',
        sale_type: amountReceived >= total ? 'cash' : 'credit',
        status: amountReceived >= total
          ? 'paid'
          : (amountReceived > 0 ? 'partial' : 'issued'),
        notes: null,
        linked_invoice_id: null,
        seller_inventory_deductions: Object.fromEntries(
          inventoryRefs.map((ref) => [ref.id, 1]),
        ),
        created_by: uid,
        created_at: now,
        updated_at: now,
      });
      transaction.set(saleRef, {
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        type: 'cash_out',
        sale_type: amountReceived >= total ? 'cash' : 'credit',
        amount: total,
        description: 'Invoice INV-2026-0001',
        items,
        invoice_id: invoiceRef.id,
        invoice_number: 'INV-2026-0001',
        created_by: uid,
        created_at: now,
        deleted: false,
      });
      if (amountReceived > 0) {
        transaction.set(paymentRef, {
          tenant_id: 'tenant-1',
          shop_id: 'shop-1',
          shop_name: 'Seed Shop',
          route_id: 'route-1',
          type: 'cash_in',
          sale_type: 'cash',
          amount: amountReceived,
          description: 'Payment for INV-2026-0001',
          items: [],
          invoice_id: invoiceRef.id,
          invoice_number: 'INV-2026-0001',
          created_by: uid,
          created_at: now,
          deleted: false,
        });
      }
      transaction.update(shopRef, {
        balance: firebase.firestore.FieldValue.increment(total - amountReceived),
        updated_at: now,
        last_transaction_at: now,
        last_transaction_type: 'cash_out',
        last_transaction_amount: total,
        last_transaction_id: saleRef.id,
      });
      for (const inventoryRef of inventoryRefs) {
        transaction.update(inventoryRef, {
          quantity_available: firebase.firestore.FieldValue.increment(-1),
          updated_at: now,
          last_sale_invoice_id: invoiceRef.id,
        });
      }
    });
  }

  it('seller can create a stock invoice after reading its missing id', async () => {
    await seedSale({ role: 'seller', uid: 'seller-uid' });
    await assertSucceeds(saleTransaction(
      sellerCtx(testEnv).firestore(),
      'seller-uid',
    ));
  });

  it('seller can create a paid sale invoice after reading its missing id', async () => {
    await seedSale({ role: 'seller', uid: 'seller-uid' });
    await assertSucceeds(saleTransaction(
      sellerCtx(testEnv).firestore(),
      'seller-uid',
      { amountReceived: 100 },
    ));
  });

  it('admin can create a sale invoice after reading its missing id', async () => {
    await seedSale({ role: 'admin', uid: 'admin-uid' });
    await assertSucceeds(saleTransaction(
      adminCtx(testEnv).firestore(),
      'admin-uid',
    ));
  });

  it('three-line seller sale with payment stays within the Rules access budget', async () => {
    await seedSale({ role: 'seller', uid: 'seller-uid', lineCount: 3 });
    await assertSucceeds(saleTransaction(
      sellerCtx(testEnv).firestore(),
      'seller-uid',
      { lineCount: 3, amountReceived: 40 },
    ));
  });
});
