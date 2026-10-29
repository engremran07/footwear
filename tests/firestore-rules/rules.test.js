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
function supervisorCtx(env) {
  return env.authenticatedContext('supervisor-uid', {
    email: 'supervisor@test.com',
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
      !/^\s*super[_-]?admin\s*$/i.test(role)
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
  assignedRouteIds = ['route-1'],
} = {}) {
  const batch = db.batch();
  const userRef = db.collection('users').doc(userId);
  batch.set(userRef, {
    role,
    active: true,
    display_name: 'New Workspace User',
    email: `${userId}@test.com`,
    tenant_id: tenantId,
    created_by: createdBy,
    assigned_route_ids: assignedRouteIds,
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

  it('legacy tenant-admin and super-admin role aliases retain scoped admin reads', async () => {
    await seedUser('listed-seller', 'seller');
    for (const [index, role] of [
      'tenant-admin',
      'tenantadmin',
      'super-admin',
      'superadmin',
    ].entries()) {
      const uid = `legacy-admin-${index}`;
      await seedUser(uid, role, true, {
        active_workspace_id: 'tenant-1',
        active_workspace_reason: 'Legacy role compatibility check',
        active_workspace_selected_at: new Date(),
      });
      const db = testEnv.authenticatedContext(uid).firestore();
      await assertSucceeds(
        db.collection('users').where('tenant_id', '==', 'tenant-1').get(),
      );
    }
  });

  it('self profile updates cannot set email_verified beyond the auth claim', async () => {
    await seedUser('seller-uid', 'seller');
    const db = testEnv.authenticatedContext('seller-uid', {
      email: 'seller@test.com',
      email_verified: false,
    }).firestore();
    const profile = db.collection('users').doc('seller-uid');

    await assertFails(
      profile.update({
        email_verified: true,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('verified users can sync email_verified from the auth claim', async () => {
    await seedUser('seller-uid', 'seller', true, { email: 'old@test.com' });
    const db = testEnv.authenticatedContext('seller-uid', {
      email: 'new@test.com',
      email_verified: true,
    }).firestore();
    const profile = db.collection('users').doc('seller-uid');

    await assertSucceeds(
      profile.update({
        email: 'new@test.com',
        email_verified: true,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('self profile email sync must match the verified auth email claim', async () => {
    await seedUser('seller-uid', 'seller');
    const db = testEnv.authenticatedContext('seller-uid', {
      email: 'seller@test.com',
      email_verified: true,
    }).firestore();

    await assertFails(
      db.collection('users').doc('seller-uid').update({
        email: 'attacker@test.com',
        email_verified: true,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('self profile updates can still change allowed profile fields', async () => {
    await seedUser('seller-uid', 'seller');
    const db = testEnv.authenticatedContext('seller-uid', {
      email: 'seller@test.com',
      email_verified: true,
    }).firestore();
    const profile = db.collection('users').doc('seller-uid');

    await assertSucceeds(
      profile.update({
        display_name: 'Updated profile',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
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

  it('legacy admin cannot deactivate a supervisor, while manager can manage a seller', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('supervisor-target', 'supervisor', true, {
      assigned_route_ids: [],
    });
    const adminDb = adminCtx(testEnv).firestore();
    await assertFails(
      setUserActiveWithSeat(adminDb, 'tenant-1', 'supervisor-target', false),
    );

    await seedUser('manager-uid', 'manager');
    await seedUser('manager-seller', 'seller');
    const managerDb = testEnv.authenticatedContext('manager-uid').firestore();
    await assertSucceeds(
      setUserActiveWithSeat(managerDb, 'tenant-1', 'manager-seller', false),
    );
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

  it('workspace admin can create a supervisor with an atomic seat increment', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertSucceeds(
      createUserWithSeat(db, 'supervisor-uid', {
        role: 'supervisor',
        createdBy: 'tenant-admin-uid',
        assignedRouteIds: [],
      }),
    );
  });

  it('workspace admin cannot create or promote an admin role', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('seller-uid', 'seller');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertFails(
      createUserWithSeat(db, 'new-admin-uid', {
        role: 'admin',
        createdBy: 'tenant-admin-uid',
        assignedRouteIds: [],
      }),
    );
    await assertFails(
      db.collection('users').doc('seller-uid').update({
        role: 'admin',
        assigned_route_ids: [],
        assigned_route_names: [],
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('workspace admin can promote and demote a seller to supervisor', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('seller-uid', 'seller');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertSucceeds(
      db.collection('users').doc('seller-uid').update({
        role: 'supervisor',
        assigned_route_ids: [],
        assigned_route_names: [],
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertSucceeds(
      db.collection('users').doc('seller-uid').update({
        role: 'seller',
        assigned_route_ids: ['route-1'],
        assigned_route_names: ['Route 1'],
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('tenant admin can deactivate an eligible seller with an atomic seat release', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('seller-target', 'seller');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertSucceeds(
      setUserActiveWithSeat(db, 'tenant-1', 'seller-target', false),
    );
  });

  it('tenant admin can deactivate an eligible supervisor with an atomic seat release', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('supervisor-target', 'supervisor', true, {
      assigned_route_ids: [],
      assigned_route_names: [],
    });
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertSucceeds(
      setUserActiveWithSeat(db, 'tenant-1', 'supervisor-target', false),
    );
    let target;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      target = await ctx.firestore()
        .collection('users')
        .doc('supervisor-target')
        .get();
    });
    const tenant = await db.collection('tenants').doc('tenant-1').get();
    assert.strictEqual(target.data().active, false);
    assert.strictEqual(tenant.data().active_user_count, 1);
  });

  it('tenant admin can reactivate an eligible supervisor with an atomic seat addition', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('supervisor-target', 'supervisor', false, {
      assigned_route_ids: [],
      assigned_route_names: [],
    });
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertSucceeds(
      setUserActiveWithSeat(db, 'tenant-1', 'supervisor-target', true),
    );
    const tenant = await db.collection('tenants').doc('tenant-1').get();
    assert.strictEqual(tenant.data().active_user_count, 2);
  });

  it('workspace admin cannot change a peer admin role', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('workspace-admin-uid', 'admin');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertFails(
      db.collection('users').doc('workspace-admin-uid').update({
        role: 'supervisor',
        assigned_route_ids: [],
        assigned_route_names: [],
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('workspace admin cannot deactivate a peer admin with a seat-counter write', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('workspace-admin-uid', 'admin');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertFails(
      setUserActiveWithSeat(db, 'tenant-1', 'workspace-admin-uid', false),
    );
  });

  it('workspace role writes require exact canonical assignable values', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('seller-uid', 'seller');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertFails(
      db.collection('users').doc('seller-uid').update({
        role: ' SELLER ',
        assigned_route_ids: ['route-1'],
        assigned_route_names: ['Route 1'],
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });
  it('workspace roster queries retain active legacy profiles without display_name', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('legacy-user', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('users').doc('legacy-user').update({
        display_name: firebase.firestore.FieldValue.delete(),
      });
    });
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });

    const db = tenantAdminCtx(testEnv).firestore();
    const rosterQuery = db
      .collection('users')
      .where('tenant_id', '==', 'tenant-1')
      .where('active', '==', true);
    const orderedSnapshot = await assertSucceeds(
      rosterQuery.orderBy('display_name').get(),
    );
    const completeSnapshot = await assertSucceeds(rosterQuery.get());

    assert.strictEqual(orderedSnapshot.size, 1);
    assert.strictEqual(completeSnapshot.size, 2);
    assert(
      completeSnapshot.docs.some((document) => document.id === 'legacy-user'),
    );
  });

  it('workspace admin cannot change the permanent owner or assign platform roles', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('seller-uid', 'seller');
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertFails(
      db.collection('users').doc('tenant-admin-uid').update({
        role: 'seller',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertFails(
      db.collection('users').doc('seller-uid').update({
        role: 'tenant_admin',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertFails(
      db.collection('users').doc('seller-uid').update({
        role: 'super_admin',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('workspace admin cannot manage a user in another tenant', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await seedUser('outside-seller', 'seller', true, {
      tenant_id: 'tenant-2',
    });
    await seedTenant({ ownerUserId: 'tenant-admin-uid' });
    const db = tenantAdminCtx(testEnv).firestore();

    await assertFails(
      db.collection('users').doc('outside-seller').update({
        role: 'admin',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('selected platform admin can reconcile a stale workspace seat counter', async () => {
    await seedTenant({ activeUserCount: 4 });
    await seedUser('platform-seat-admin', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Seat counter reconciliation',
      active_workspace_selected_at: new Date(),
    });
    const db = testEnv.authenticatedContext('platform-seat-admin').firestore();

    await assertSucceeds(
      db.collection('tenants').doc('tenant-1').update({
        active_user_count: 2,
        max_active_users: 10,
        seat_count_revision: 1,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
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
  it('legacy global business documents remain readable by unassigned admin profiles', async () => {
    await seedUser('admin-uid', 'admin', true, { tenant_id: null });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('products').doc('legacy-global-product').set({
        name: 'Legacy Global Product',
        tenant_id: '__global__',
      });
    });
    const db = adminCtx(testEnv).firestore();

    await assertSucceeds(
      db.collection('products').doc('legacy-global-product').get(),
    );
  });

  it('new business creates cannot use __global__ as a tenant', async () => {
    await seedUser('admin-uid', 'admin', true, { tenant_id: null });
    const db = adminCtx(testEnv).firestore();

    await assertFails(
      db.collection('products').doc('global-product').set({
        name: 'Global Product',
        tenant_id: '__global__',
      }),
    );
    await assertFails(
      db.collection('product_variants').doc('global-variant').set({
        tenant_id: '__global__',
        product_id: 'global-product',
        variant_name: 'Global Variant',
        quantity_available: 1,
      }),
    );
    await assertFails(
      db.collection('routes').doc('global-route').set({
        tenant_id: '__global__',
        name: 'Global Route',
        route_number: 1,
        total_shops: 0,
      }),
    );
    await assertFails(
      db.collection('customers').doc('global-shop').set({
        tenant_id: '__global__',
        balance: 0,
      }),
    );
    await assertFails(
      db.collection('inventory_transactions').doc('global-stock-log').set({
        tenant_id: '__global__',
        type: 'stock_adjustment',
        quantity: 1,
      }),
    );
  });

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

describe('supervisor operational access', () => {
  it('can read tenant operations and update routes without reassigning sellers', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedShop('shop-1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('routes').doc('route-1').set({
        name: 'Route One',
        route_number: 1,
        total_shops: 1,
        active: true,
        assigned_seller_ids: ['seller-uid'],
        assigned_seller_names: ['Seller'],
        tenant_id: 'tenant-1',
      });
      await db.collection('products').doc('product-1').set({
        name: 'Product One',
        tenant_id: 'tenant-1',
      });
      await db.collection('seller_inventory').doc('stock-1').set({
        seller_id: 'seller-uid',
        variant_id: 'variant-1',
        quantity_available: 12,
        tenant_id: 'tenant-1',
      });
      await db.collection('inventory_transactions').doc('movement-1').set({
        type: 'stock_adjustment',
        quantity: 1,
        tenant_id: 'tenant-1',
      });
      await db.collection('invoices').doc('invoice-1').set({
        type: 'sale',
        tenant_id: 'tenant-1',
      });
    });

    const db = supervisorCtx(testEnv).firestore();
    await assertSucceeds(
      db.collection('routes').where('tenant_id', '==', 'tenant-1').get(),
    );
    await assertSucceeds(
      db.collection('customers').where('tenant_id', '==', 'tenant-1').get(),
    );
    await assertSucceeds(
      db.collection('products').where('tenant_id', '==', 'tenant-1').get(),
    );
    await assertSucceeds(
      db.collection('seller_inventory')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
    );
    await assertSucceeds(
      db.collection('inventory_transactions')
        .where('tenant_id', '==', 'tenant-1')
        .get(),
    );
    await assertSucceeds(
      db.collection('invoices').where('tenant_id', '==', 'tenant-1').get(),
    );
    await assertSucceeds(
      db.collection('products').doc('product-1').update({
        name: 'Updated Product',
      }),
    );
    await assertSucceeds(
      db.collection('routes').doc('route-1').update({ name: 'Updated Route' }),
    );
    await assertSucceeds(
      db.collection('inventory_transactions').doc('movement-2').set({
        type: 'stock_adjustment',
        quantity: 1,
        tenant_id: 'tenant-1',
      }),
    );
  });

  it('cannot manage user accounts or route assignments', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('routes').doc('route-1').set({
        name: 'Route One',
        route_number: 1,
        total_shops: 0,
        active: true,
        assigned_seller_ids: ['seller-uid'],
        assigned_seller_names: ['Seller'],
        tenant_id: 'tenant-1',
      });
      await db.collection('customers').doc('shop-1').set({
        name: 'Shop One',
        route_id: 'route-1',
        balance: 0,
        tenant_id: 'tenant-1',
      });
    });

    const db = supervisorCtx(testEnv).firestore();
    await assertFails(
      db.collection('users').where('tenant_id', '==', 'tenant-1').get(),
    );
    await assertFails(
      db.collection('routes').doc('route-1').update({
        assigned_seller_ids: [],
        assigned_seller_names: [],
      }),
    );
    await assertFails(
      db.collection('customers').doc('shop-1').update({
        route_id: 'route-2',
      }),
    );
  });

  it('can create a sale invoice only with the linked ledger and balance batch', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedShop('shop-1', { balance: 0 });
    await seedSettings({ allow_non_stock_invoices: true });
    const db = supervisorCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('supervisor-sale');
    const saleRef = db.collection('transactions').doc('supervisor-sale-tx');
    const batch = db.batch();
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      created_by: 'supervisor-uid',
      seller_id: 'supervisor-uid',
      type: 'sale',
      invoice_number: 'INV-0001',
      invoice_sequence: 1,
      sale_transaction_id: saleRef.id,
      fulfillment_mode: 'non_stock',
      seller_inventory_deductions: {},
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 999999.99 }],
      subtotal: 999999.99,
      discount: 0,
      total: 999999.99,
      amount_received: 0,
      financial_minor_units: {
        subtotal: 99999999,
        discount: 0,
        total: 99999999,
        amount_received: 0,
        outstanding_amount: 99999999,
        'items.0.unit_price': 99999999,
      },
    });
    batch.set(saleRef, {
      created_by: 'supervisor-uid',
      type: 'cash_out',
      amount: 999999.99,
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-0001',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      financial_minor_units: {
        amount: 99999999,
        'items.0.unit_price': 99999999,
      },
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 999999.99,
      financial_minor_units: {
        balance: 99999999,
        last_transaction_amount: 99999999,
      },
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 999999.99,
      last_transaction_id: saleRef.id,
    });

    await assertSucceeds(batch.commit());
  });

  it('workspace admin can backfill integer companions without changing amounts', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedShop('shop-1', { balance: 12.5 });
    await seedTransaction('tx-minor-units', { amount: 10.25 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('invoice-minor-units').set({
        tenant_id: 'tenant-1',
        type: 'sale',
        shop_id: 'shop-1',
        route_id: 'route-1',
        total: 10.25,
        amount_received: 0,
        items: [],
      });
    });

    const db = adminCtx(testEnv).firestore();
    const batch = db.batch();
    batch.update(db.collection('customers').doc('shop-1'), {
      financial_minor_units: { balance: 1250 },
    });
    batch.update(db.collection('transactions').doc('tx-minor-units'), {
      financial_minor_units: { amount: 1025 },
    });
    batch.update(db.collection('invoices').doc('invoice-minor-units'), {
      financial_minor_units: {
        total: 1025,
        amount_received: 0,
      },
    });

    await assertSucceeds(batch.commit());
    const shop = await db.collection('customers').doc('shop-1').get();
    const transaction = await db
      .collection('transactions')
      .doc('tx-minor-units')
      .get();
    const invoice = await db
      .collection('invoices')
      .doc('invoice-minor-units')
      .get();
    assert.strictEqual(shop.data().balance, 12.5);
    assert.strictEqual(transaction.data().amount, 10.25);
    assert.strictEqual(invoice.data().total, 10.25);
    await assertFails(
      sellerCtx(testEnv)
        .firestore()
        .collection('invoices')
        .doc('invoice-minor-units')
        .update({
          financial_minor_units: { total: 999999 },
        }),
    );
  });

  it('cannot create a linked sale invoice above the financial amount limit', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedShop('shop-1', { balance: 0 });
    await seedSettings({ allow_non_stock_invoices: true });
    const db = supervisorCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('supervisor-sale-over-limit');
    const saleRef = db.collection('transactions').doc('supervisor-sale-over-limit-tx');
    const batch = db.batch();
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      created_by: 'supervisor-uid',
      seller_id: 'supervisor-uid',
      type: 'sale',
      invoice_number: 'INV-0001',
      invoice_sequence: 1,
      sale_transaction_id: saleRef.id,
      fulfillment_mode: 'non_stock',
      seller_inventory_deductions: {},
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      items: [{ variant_id: 'v1', qty: 1, unit_price: 1000000 }],
      subtotal: 1000000,
      discount: 0,
      total: 1000000,
      amount_received: 0,
    });
    batch.set(saleRef, {
      created_by: 'supervisor-uid',
      type: 'cash_out',
      amount: 1000000,
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-0001',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 1000000,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 1000000,
      last_transaction_id: saleRef.id,
    });

    await assertFails(batch.commit());
  });

  it('cannot advance the invoice counter below the shared high-water mark', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedSettings({
      last_invoice_number: 4,
      last_cash_receipt_number: 1,
    });
    const db = supervisorCtx(testEnv).firestore();
    await assertFails(
      db.collection('settings').doc('tenant-1').update({
        last_invoice_number: 2,
        last_invoice_id: 'stale-invoice-counter',
      }),
    );
    await assertFails(
      db.collection('settings').doc('tenant-1').update({
        last_invoice_number: 5,
        last_invoice_id: 'orphan-invoice-id',
      }),
    );
  });

  it('supervisor can create a linked cash receipt and reduce shop balance', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedShop('shop-1', { balance: 100 });
    await seedSettings({
      last_invoice_number: 4,
      last_cash_receipt_number: 1,
    });
    const db = supervisorCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('supervisor-receipt');
    const transactionRef = db.collection('transactions')
      .doc('supervisor-receipt-tx');
    const receiptBatch = (sequence) => {
      const batch = db.batch();
      const invoiceNumber = `REC-${String(sequence).padStart(4, '0')}`;
      batch.update(db.collection('settings').doc('tenant-1'), {
        last_cash_receipt_number: sequence,
        last_cash_receipt_id: invoiceRef.id,
      });
      batch.set(invoiceRef, {
        tenant_id: 'tenant-1',
        created_by: 'supervisor-uid',
        type: 'cash_receipt',
        fulfillment_mode: 'none',
        cash_receipt_transaction_id: transactionRef.id,
        cash_receipt_sequence: sequence,
        invoice_number: invoiceNumber,
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        seller_id: 'supervisor-uid',
        items: [],
        subtotal: 0,
        discount: 0,
        total: 25,
        amount_received: 25,
        status: 'paid',
      });
      batch.set(transactionRef, {
        tenant_id: 'tenant-1',
        created_by: 'supervisor-uid',
        type: 'cash_in',
        amount: 25,
        shop_id: 'shop-1',
        route_id: 'route-1',
        invoice_id: invoiceRef.id,
        invoice_number: invoiceNumber,
      });
      batch.update(db.collection('customers').doc('shop-1'), {
        balance: 75,
        updated_at: new Date(),
        last_transaction_at: new Date(),
        last_transaction_type: 'cash_in',
        last_transaction_amount: 25,
        last_transaction_id: transactionRef.id,
      });
      return batch;
    };
    await assertFails(
      db.collection('settings').doc('tenant-1').update({
        last_cash_receipt_number: 2,
        last_cash_receipt_id: 'stale-receipt-id',
      }),
    );
    await assertFails(
      db.collection('settings').doc('tenant-1').update({
        last_cash_receipt_number: 5,
        last_cash_receipt_id: 'orphan-receipt-id',
      }),
    );
    await assertSucceeds(receiptBatch(5).commit());
  });

  it('[INVOICE_TYPE_ALLOWLIST] operational roles cannot create unsupported invoice types', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    const db = supervisorCtx(testEnv).firestore();

    for (const [index, type] of ['return', 'payment', 'write_off'].entries()) {
      await assertFails(
        db.collection('invoices').doc(`unsupported-type-${index}`).set({
          tenant_id: 'tenant-1',
          created_by: 'supervisor-uid',
          type,
          shop_id: 'shop-1',
          route_id: 'route-1',
          items: [{ variant_id: 'variant-1', qty: 1, unit_price: 10 }],
          subtotal: 10,
          discount: 0,
          total: 10,
          amount_received: 0,
        }),
      );
    }
  });

  it('cannot write off shop debt or create correction transaction types', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedShop('shop-1', { balance: 100, bad_debt: false });
    const db = supervisorCtx(testEnv).firestore();
    const writeOff = db.collection('transactions').doc('supervisor-write-off');
    const batch = db.batch();
    batch.set(writeOff, {
      tenant_id: 'tenant-1',
      created_by: 'supervisor-uid',
      type: 'write_off',
      amount: 100,
      shop_id: 'shop-1',
      route_id: 'route-1',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      bad_debt: true,
      bad_debt_amount: 100,
      balance: 0,
      last_transaction_type: 'write_off',
      last_transaction_amount: 100,
      last_transaction_id: writeOff.id,
    });
    await assertFails(batch.commit());

    for (const type of ['return', 'payment']) {
      await assertFails(
        db.collection('transactions').doc(`supervisor-${type}`).set({
          tenant_id: 'tenant-1',
          created_by: 'supervisor-uid',
          type,
          amount: 10,
          shop_id: 'shop-1',
          route_id: 'route-1',
        }),
      );
    }
  });

  it('cannot create a credit note or void an issued invoice', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedShop('shop-1', { balance: 100 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('supervisor-original').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        route_id: 'route-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        created_at: new Date(),
        credit_note_total: 0,
      });
    });
    const db = supervisorCtx(testEnv).firestore();
    const creditRef = db.collection('invoices').doc('supervisor-credit-note');
    const returnRef = db.collection('transactions').doc('supervisor-return');
    const creditBatch = db.batch();
    creditBatch.update(db.collection('invoices').doc('supervisor-original'), {
      credit_note_total: 40,
    });
    creditBatch.set(creditRef, {
      tenant_id: 'tenant-1',
      created_by: 'supervisor-uid',
      type: 'credit_note',
      linked_invoice_id: 'supervisor-original',
      return_transaction_id: returnRef.id,
      shop_id: 'shop-1',
      route_id: 'route-1',
      items: [{ variant_id: 'variant-1', qty: 1, unit_price: 40 }],
      subtotal: 40,
      discount: 0,
      total: 40,
      amount_received: 0,
    });
    creditBatch.set(returnRef, {
      tenant_id: 'tenant-1',
      created_by: 'supervisor-uid',
      type: 'return',
      amount: 40,
      shop_id: 'shop-1',
      route_id: 'route-1',
      invoice_id: creditRef.id,
    });
    creditBatch.update(db.collection('customers').doc('shop-1'), {
      balance: 60,
      last_transaction_type: 'return',
      last_transaction_amount: 40,
      last_transaction_id: returnRef.id,
    });
    await assertFails(creditBatch.commit());

    await assertFails(
      db.collection('invoices').doc('supervisor-original').update({
        status: 'void',
        void_by: 'supervisor-uid',
        void_at: new Date(),
        updated_at: new Date(),
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

  it('operational notification shop lookups stay within the Rules access budget', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('supervisor-uid', 'supervisor');
    const shopIds = Array.from({ length: 50 }, (_, index) => `notice-shop-${index}`);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        const batch = db.batch();
        for (const shopId of shopIds) {
          batch.set(db.collection('customers').doc(shopId), {
            name: shopId,
            route_id: 'route-1',
            tenant_id: 'tenant-1',
            balance: 0,
            active: true,
          });
        }
        await batch.commit();
    });

    for (const context of [adminCtx(testEnv), supervisorCtx(testEnv)]) {
        const db = context.firestore();
        for (let start = 0; start < shopIds.length; start += 5) {
          const chunk = shopIds.slice(start, start + 5);
          const snapshot = await assertSucceeds(
            db.collection('customers')
              .where('tenant_id', '==', 'tenant-1')
              .where(firebase.firestore.FieldPath.documentId(), 'in', chunk)
              .get(),
          );
          assert.strictEqual(snapshot.size, chunk.length);
        }
    }
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

  it('seller cannot create an over-limit transaction with a matching balance update', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 0 });
    const db = sellerCtx(testEnv).firestore();
    const transactionRef = db.collection('transactions').doc('tx-seller-over-limit');
    const batch = db.batch();
    batch.set(transactionRef, {
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      amount: 1000000,
      type: 'cash_out',
      description: 'Over-limit sale',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 1000000,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 1000000,
      last_transaction_id: transactionRef.id,
    });

    await assertFails(batch.commit());
  });

  it('workspace admin cannot create an over-limit transaction with a matching balance update', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 0 });
    const db = adminCtx(testEnv).firestore();
    const transactionRef = db.collection('transactions').doc('tx-admin-over-limit');
    const batch = db.batch();
    batch.set(transactionRef, {
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      amount: 1000000,
      type: 'cash_out',
      description: 'Over-limit sale',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 1000000,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 1000000,
      last_transaction_id: transactionRef.id,
    });

    await assertFails(batch.commit());
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

  it('[INVOICE_COUNTER_LINK] counter update requires a matching invoice in the same batch', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    await seedSettings();
    const adminDb = adminCtx(testEnv).firestore();
    const sellerDb = sellerCtx(testEnv).firestore();

    await assertFails(
      adminDb.collection('settings').doc('tenant-1').update({
        last_invoice_number: 1,
        last_invoice_id: 'missing-admin-invoice',
      }),
    );
    await assertFails(
      sellerDb.collection('settings').doc('tenant-1').update({
        last_invoice_number: 1,
      }),
    );
  });
});

describe('multi-workspace tenant isolation', () => {
  it('[WORKSPACE_SCALE_15] scopes business reads across fifteen workspaces', async () => {
    const workspaces = Array.from({ length: 15 }, (_, index) => {
      const suffix = String(index + 1).padStart(2, '0');
      return {
        tenantId: `workspace-${suffix}`,
        userId: `workspace-admin-${suffix}`,
        shopId: `workspace-shop-${suffix}`,
        invoiceId: `workspace-invoice-${suffix}`,
      };
    });

    for (const workspace of workspaces) {
      await seedUser(workspace.userId, 'tenant_admin', true, {
        tenant_id: workspace.tenantId,
      });
    }

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      for (const workspace of workspaces) {
        await db.collection('customers').doc(workspace.shopId).set({
          tenant_id: workspace.tenantId,
          route_id: `${workspace.tenantId}-route`,
          name: workspace.tenantId,
          balance: 0,
        });
        await db.collection('invoices').doc(workspace.invoiceId).set({
          tenant_id: workspace.tenantId,
          created_by: workspace.userId,
          seller_id: workspace.userId,
          type: 'sale',
          status: 'issued',
        });
      }
    });

    for (let index = 0; index < workspaces.length; index++) {
      const workspace = workspaces[index];
      const otherWorkspace = workspaces[(index + 1) % workspaces.length];
      const db = testEnv.authenticatedContext(workspace.userId).firestore();

      await assertSucceeds(
        db.collection('customers').doc(workspace.shopId).get(),
      );
      await assertSucceeds(
        db.collection('invoices').doc(workspace.invoiceId).get(),
      );
      await assertFails(
        db.collection('customers').doc(otherWorkspace.shopId).get(),
      );
      await assertFails(
        db.collection('invoices').doc(otherWorkspace.invoiceId).get(),
      );
    }
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

  it('admin: cannot change an issued invoice field outside the update allowlist', async () => {
    await seedUser('admin-uid', 'admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('issued-edit').set({
        tenant_id: 'tenant-1',
        created_by: 'seller-uid',
        type: 'sale',
        status: 'issued',
        invoice_number: 'INV-2026-0010',
        shop_id: 'shop-1',
        route_id: 'route-1',
        total: 100,
        amount_received: 0,
        outstanding_amount: 100,
      });
    });
    await assertFails(
      adminCtx(testEnv).firestore().collection('invoices').doc('issued-edit')
        .update({
          invoice_number: 'INV-2026-TAMPERED',
        }),
    );
  });

  it('admin: cannot settle an invoice without its linked payment and shop update', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 100 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().collection('invoices').doc('unlinked-settlement').set({
          tenant_id: 'tenant-1',
          created_by: 'seller-uid',
          type: 'sale',
          status: 'issued',
          shop_id: 'shop-1',
          route_id: 'route-1',
          total: 100,
          created_at: new Date(),
          amount_received: 0,
          outstanding_amount: 100,
        });
    });

    await assertFails(
        adminCtx(testEnv).firestore()
          .collection('invoices')
          .doc('unlinked-settlement')
          .update({
            status: 'paid',
            amount_received: 100,
            outstanding_amount: 0,
          }),
    );
  });

  it('admin: cannot void an invoice without its linked reversal and shop update', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 100 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().collection('invoices').doc('unlinked-void').set({
          tenant_id: 'tenant-1',
          created_by: 'seller-uid',
          type: 'sale',
          status: 'issued',
          shop_id: 'shop-1',
          route_id: 'route-1',
          total: 100,
          amount_received: 0,
          outstanding_amount: 100,
        });
    });

    await assertFails(
        adminCtx(testEnv).firestore()
          .collection('invoices')
          .doc('unlinked-void')
          .update({
            status: 'void',
            void_by: 'admin-uid',
            void_at: new Date(),
            updated_at: new Date(),
          }),
    );
  });

  it('admin: cannot change a credit total without its linked credit note', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 100 });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().collection('invoices').doc('unlinked-credit-total').set({
          tenant_id: 'tenant-1',
          created_by: 'seller-uid',
          type: 'sale',
          status: 'issued',
          shop_id: 'shop-1',
          route_id: 'route-1',
          total: 100,
          amount_received: 0,
          outstanding_amount: 100,
          credit_note_total: 0,
        });
    });

    await assertFails(
        adminCtx(testEnv).firestore()
          .collection('invoices')
          .doc('unlinked-credit-total')
          .update({ credit_note_total: 40 }),
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
    await seedSettings();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('original-sale').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        route_id: 'route-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        created_at: new Date(),
        credit_note_total: 0,
        amount_received: 0,
        outstanding_amount: 100,
      });
    });
    const db = adminCtx(testEnv).firestore();
    const linkedHistory = await assertSucceeds(
      db
        .collection('invoices')
        .where('tenant_id', '==', 'tenant-1')
        .where('linked_invoice_id', '==', 'original-sale')
        .get(),
    );
    assert.strictEqual(linkedHistory.size, 0);
    const batch = db.batch();
    const creditRef = db.collection('invoices').doc('credit-valid');
    const returnRef = db.collection('transactions').doc('credit-valid-tx');
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: creditRef.id,
    });
    batch.update(db.collection('invoices').doc('original-sale'), {
      credit_note_total: 40,
      latest_credit_note_invoice_id: creditRef.id,
      outstanding_amount: 60,
    });
    batch.set(creditRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'credit_note',
      invoice_sequence: 1,
      invoice_number: 'CN-0001',
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
    const updatedOriginal = await db
      .collection('invoices')
      .doc('original-sale')
      .get();
    assert.strictEqual(updatedOriginal.data().outstanding_amount, 60);
  });

  it('admin: cannot create a credit note more than 30 days after the sale', async () => {
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1', { balance: 100 });
    await seedSettings();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('expired-sale').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        route_id: 'route-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        credit_note_total: 0,
        amount_received: 0,
        outstanding_amount: 100,
        created_at: new Date(Date.now() - 31 * 24 * 60 * 60 * 1000),
      });
    });

    const db = adminCtx(testEnv).firestore();
    const batch = db.batch();
    const creditRef = db.collection('invoices').doc('expired-credit');
    const returnRef = db.collection('transactions').doc('expired-credit-tx');
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: creditRef.id,
    });
    batch.update(db.collection('invoices').doc('expired-sale'), {
      credit_note_total: 40,
      latest_credit_note_invoice_id: creditRef.id,
      outstanding_amount: 60,
    });
    batch.set(creditRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      type: 'credit_note',
      invoice_sequence: 1,
      return_transaction_id: returnRef.id,
      linked_invoice_id: 'expired-sale',
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
    await assertFails(batch.commit());
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
        created_at: new Date(),
        amount_received: 0,
        outstanding_amount: 100,
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
        created_at: new Date(),
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
        receipt_phone_2: '+966511111111',
        receipt_phone_3: '+966522222222',
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
    const buildBatch = (invoiceSellerId) => {
      const batch = db.batch();
      batch.update(db.collection('settings').doc('tenant-1'), {
        last_invoice_number: 1,
        last_invoice_id: invoiceRef.id,
      });
      batch.set(invoiceRef, {
        created_by: 'seller-uid',
        type: 'sale',
        invoice_number: 'INV-2026-0001',
        invoice_sequence: 1,
        sale_transaction_id: saleRef.id,
        invoice_header_snapshot: {
          name_en: 'Workspace Name',
          visible_fields: [],
          document_language_pair: 'english_urdu',
          receipt_phone_2: '+966511111111',
          receipt_phone_3: '+966522222222',
          company_name: 'Workspace Name',
          logo_base64: 'workspace-logo',
        },
        shop_id: 'shop-1',
        shop_name: 'Shop One',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        seller_id: invoiceSellerId,
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
      return batch;
    };
    await assertFails(buildBatch('another-seller').commit());
    await assertSucceeds(buildBatch('seller-uid').commit());
    await assertSucceeds(
      db.collection('notifications').doc(`invoice_${invoiceRef.id}`).set({
        type: 'invoice',
        shop_id: 'shop-1',
        shop_name: 'Shop One',
        route_id: 'route-1',
        seller_id: 'seller-uid',
        seller_name: 'Test User',
        amount: 100,
        transaction_type: 'cash_out',
        invoice_number: 'INV-2026-0001',
        ref_id: invoiceRef.id,
        target_role: 'admin',
        read: false,
        tenant_id: 'tenant-1',
        created_by: 'seller-uid',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('seller: can atomically create a 30-line sale with 30 stock deductions', async () => {
    await seedUser('seller-uid', 'seller', true, {
      assigned_route_id: 'route-1',
    });
    await seedShop('shop-1', { balance: 0 });
    await seedSettings();

    const inventoryIds = Array.from(
      { length: 30 },
      (_, index) => `inventory-${index + 1}`,
    );
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const batch = db.batch();
      for (const inventoryId of inventoryIds) {
        batch.set(db.collection('seller_inventory').doc(inventoryId), {
          seller_id: 'seller-uid',
          tenant_id: 'tenant-1',
          quantity_available: 5,
          active: true,
        });
      }
      await batch.commit();
    });

    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('large-sale');
    const saleRef = db.collection('transactions').doc('large-sale-tx');
    const items = inventoryIds.map((_, index) => ({
      variant_id: `variant-${index + 1}`,
      qty: 1,
      unit_price: 10,
    }));
    const deductions = Object.fromEntries(
      inventoryIds.map((inventoryId) => [inventoryId, 1]),
    );
    const batch = db.batch();

    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'sale',
      invoice_number: 'INV-2026-0030',
      invoice_sequence: 1,
      sale_transaction_id: saleRef.id,
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      seller_id: 'seller-uid',
      fulfillment_mode: 'stock',
      seller_inventory_deductions: deductions,
      items,
      subtotal: 300,
      discount: 0,
      total: 300,
      amount_received: 0,
    });
    batch.set(saleRef, {
      created_by: 'seller-uid',
      type: 'cash_out',
      amount: 300,
      invoice_id: invoiceRef.id,
      invoice_number: 'INV-2026-0030',
      shop_id: 'shop-1',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: 300,
      updated_at: new Date(),
      last_transaction_at: new Date(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 300,
      last_transaction_id: saleRef.id,
    });
    for (const inventoryId of inventoryIds) {
      batch.update(db.collection('seller_inventory').doc(inventoryId), {
        quantity_available: 4,
        updated_at: new Date(),
        last_sale_invoice_id: invoiceRef.id,
      });
    }

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
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      created_by: 'admin-uid',
      type: 'sale',
      invoice_number: 'INV-2026-0003',
      invoice_sequence: 1,
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
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      tenant_id: 'tenant-1',
      created_by: 'admin-uid',
      invoice_number: 'INV-2026-ADMIN-PARTIAL',
      invoice_sequence: 1,
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
      payment_transaction_ids: [paymentRef.id],
      latest_payment_transaction_id: paymentRef.id,
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
      void_reversal_transaction_id: reversalRef.id,
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
      voided: true,
      voided_invoice_id: invoiceRef.id,
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
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      invoice_number: 'INV-2026-TENANT-ADMIN',
      invoice_sequence: 1,
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
      last_cash_receipt_id: invoiceRef.id,
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
      invoice_number: 'REC-2026-0001',
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
    await seedSettings();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('tenant-admin-original').set({
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        route_id: 'route-1',
        type: 'sale',
        status: 'issued',
        total: 100,
        created_at: new Date(),
        credit_note_total: 0,
      });
    });
    const db = tenantAdminCtx(testEnv).firestore();
    const batch = db.batch();
    const originalRef = db.collection('invoices').doc('tenant-admin-original');
    const creditRef = db.collection('invoices').doc('tenant-admin-credit');
    const returnRef = db.collection('transactions').doc('tenant-admin-return');
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: creditRef.id,
    });
    batch.update(originalRef, {
      credit_note_total: 40,
      latest_credit_note_invoice_id: creditRef.id,
      outstanding_amount: 60,
    });
    batch.set(creditRef, {
      tenant_id: 'tenant-1',
      created_by: 'tenant-admin-uid',
      type: 'credit_note',
      invoice_sequence: 1,
      invoice_number: 'CN-0001',
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
      void_reversal_transaction_id: reversalRef.id,
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
      voided: true,
      voided_invoice_id: invoiceRef.id,
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
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'sale',
      invoice_number: 'INV-2026-0002',
      invoice_sequence: 1,
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
      last_cash_receipt_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'cash_receipt',
      fulfillment_mode: 'none',
      cash_receipt_transaction_id: transactionRef.id,
      cash_receipt_sequence: 1,
      invoice_number: 'REC-0001',
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
      invoice_number: 'REC-0001',
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
      last_cash_receipt_id: invoiceRef.id,
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
      last_cash_receipt_id: invoiceRef.id,
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
    await seedSettings();
    const db = sellerCtx(testEnv).firestore();
    const invoiceRef = db.collection('invoices').doc('inv-linked');
    const saleRef = db.collection('transactions').doc('tx-sale');
    const paymentRef = db.collection('transactions').doc('tx-payment');
    const batch = db.batch();
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      created_by: 'seller-uid',
      type: 'sale',
      invoice_number: 'INV-2026-0001',
      invoice_sequence: 1,
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

  it('selected super-admin can delete scoped mutable data but not append-only records or the workspace root', async () => {
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
        collection === 'inventory_transactions' ||
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
  it('seller can read a deterministic missing transaction ID but cannot run the broad idempotency query', async () => {
    await seedUser('seller-uid', 'seller');
    const db = sellerCtx(testEnv).firestore();
    await assertSucceeds(
      db.collection('transactions')
        .doc('tenant-1:standalone-transaction:retry-key')
        .get(),
    );
    await assertFails(
      db.collection('transactions')
        .where('tenant_id', '==', 'tenant-1')
        .where('idempotency_key', '==', 'retry-key')
        .limit(1)
        .get(),
    );
  });

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

  it('admin: cannot correct a transaction above the financial amount limit', async () => {
    await seedUser('admin-uid', 'admin');
    const createdAt = new Date('2026-01-01T00:00:00.000Z');
    await seedShop('shop-1', { balance: -100 });
    await seedTransaction('tx-over-limit', {
      shop_id: 'shop-1',
      created_at: createdAt,
      description: 'Original entry',
    });
    const db = adminCtx(testEnv).firestore();
    const transaction = db.collection('transactions').doc('tx-over-limit');
    const batch = db.batch();
    batch.update(transaction, {
      amount: 1000000,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      edit_history: [{
        previous_amount: 100,
        previous_type: 'cash_in',
        previous_created_at: createdAt,
        previous_description: 'Original entry',
        changed_by: 'admin-uid',
        reason: 'Correct excessive transaction amount',
        changed_at: new Date(),
      }],
    });
    batch.update(db.collection('customers').doc('shop-1'), {
      balance: -1000000,
      last_balance_correction_transaction_id: transaction.id,
      last_transaction_amount: 1000000,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertFails(batch.commit());
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

  it('seller: can submit edit request metadata when requests are enabled', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ allow_seller_edit_requests: true });
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
        financial_minor_units: {
          amount: 10000,
          edit_request_new_amount: 12000,
        },
        edit_request_new_type: 'cash_in',
        edit_request_new_description: 'Need correction',
        edit_request_new_sale_type: 'cash',
        edit_request_new_created_at: new Date(),
      }),
    );
  });

  it('seller: cannot submit a malformed financial companion', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ allow_seller_edit_requests: true });
    await seedTransaction('tx1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').update({
        edit_request_pending: true,
        edit_request_status: 'pending',
        edit_request_requested_by: 'seller-uid',
        edit_request_requested_at: new Date(),
        edit_request_new_amount: 120,
        financial_minor_units: 'not-a-map',
      }),
    );
  });

  it('seller cannot submit an over-limit transaction edit request', async () => {
    await seedUser('seller-uid', 'seller', true, { assigned_route_id: 'route-1' });
    await seedSettings({ allow_seller_edit_requests: true });
    await seedTransaction('tx1');
    await assertFails(
      sellerCtx(testEnv).firestore().collection('transactions').doc('tx1').update({
        description: 'Need correction',
        updated_at: new Date(),
        updated_by: 'seller-uid',
        edit_request_pending: true,
        edit_request_status: 'pending',
        edit_request_requested_by: 'seller-uid',
        edit_request_requested_at: new Date(),
        edit_request_new_amount: 1000000,
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
    await seedSettings();
    const db = sellerCtx(testEnv).firestore();
    const batch = db.batch();
    const invoiceRef = db.collection('invoices').doc('sale-linked-stock');
    const saleRef = db.collection('transactions').doc('sale-linked-stock-tx');
    batch.update(db.collection('settings').doc('tenant-1'), {
      last_invoice_number: 1,
      last_invoice_id: invoiceRef.id,
    });
    batch.update(db.collection('seller_inventory').doc('seller-uid_variant-1'), {
      quantity_available: 12,
      last_sale_invoice_id: invoiceRef.id,
    });
    batch.set(invoiceRef, {
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      invoice_number: 'INV-2026-STOCK-1',
      invoice_sequence: 1,
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

  it('admin: cannot create seller stock without a matching warehouse deduction', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('product_variants').doc('variant-1').set({
        tenant_id: 'tenant-1',
        product_id: 'product-1',
        quantity_available: 20,
      });
    });
    await assertFails(
      adminCtx(testEnv).firestore()
        .collection('seller_inventory')
        .doc('seller-uid_variant-1')
        .set({
          seller_id: 'seller-uid',
          seller_name: 'Seller',
          product_id: 'product-1',
          variant_id: 'variant-1',
          quantity_available: 12,
          active: true,
          tenant_id: 'tenant-1',
        }),
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
    await seedUser('seller-uid', 'seller');
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

  it('inventory transaction rows are append-only for admins and sellers', async () => {
    await seedUser('admin-uid', 'admin');
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('inventory_transactions')
        .doc('append-only-row').set({
          tenant_id: 'tenant-1',
          seller_id: 'seller-uid',
          created_by: 'admin-uid',
          type: 'transfer_out',
          quantity: 5,
        });
    });
    const adminDb = adminCtx(testEnv).firestore();
    await assertFails(
      adminDb.collection('inventory_transactions').doc('append-only-row')
        .update({ quantity: 6 }),
    );
    await assertFails(
      adminDb.collection('inventory_transactions').doc('append-only-row')
        .delete(),
    );
    await assertFails(
      sellerCtx(testEnv).firestore()
        .collection('inventory_transactions').doc('append-only-row')
        .update({ quantity: 6 }),
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// 8. notifications collection
// ═══════════════════════════════════════════════════════════════════════════
describe('notifications collection', () => {
  it('workspace admin can query and mark notifications read in its tenant', async () => {
    await seedUser('tenant-admin-uid', 'tenant_admin');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('notifications').doc('tenant-notification').set({
        target_role: 'admin',
        tenant_id: 'tenant-1',
        read: false,
        created_at: firebase.firestore.Timestamp.now(),
      });
      await db.collection('notifications').doc('other-tenant').set({
          target_role: 'admin',
          tenant_id: 'tenant-2',
          read: false,
          created_at: firebase.firestore.Timestamp.now(),
        });
    });

    const db = tenantAdminCtx(testEnv).firestore();
    const snapshot = await assertSucceeds(
      db.collection('notifications')
        .where('tenant_id', '==', 'tenant-1')
        .where('target_role', '==', 'admin')
        .orderBy('created_at', 'desc')
        .limit(50)
        .get(),
    );
    assert.deepStrictEqual(
      snapshot.docs.map((doc) => doc.id),
      ['tenant-notification'],
    );
    await assertSucceeds(
      db.collection('notifications').doc('tenant-notification').update({
        read: true,
        read_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('authorized readers can mark one or several unread notifications read', async () => {
    await seedUser('admin-uid', 'admin');
    const readAt = firebase.firestore.Timestamp.now();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const id of [
        'mark-one',
        'mark-all-one',
        'mark-all-two',
      ]) {
        await db.collection('notifications').doc(id).set({
          target_role: 'admin',
          tenant_id: 'tenant-1',
          read: false,
          created_at: readAt,
        });
      }
    });

    const db = adminCtx(testEnv).firestore();
    await assertSucceeds(
      db.collection('notifications').doc('mark-one').update({
        read: true,
        read_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );

    const markAll = db.batch();
    for (const id of ['mark-all-one', 'mark-all-two']) {
      markAll.update(db.collection('notifications').doc(id), {
        read: true,
        read_at: firebase.firestore.FieldValue.serverTimestamp(),
      });
    }
    await assertSucceeds(markAll.commit());
  });

  it('authorized readers can mark the full 50-notification feed read atomically', async () => {
    await seedUser('admin-uid', 'admin');
    const readAt = firebase.firestore.Timestamp.now();
    const ids = Array.from({ length: 50 }, (_, index) => `mark-all-${index}`);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const batch = db.batch();
      for (const id of ids) {
        batch.set(db.collection('notifications').doc(id), {
          target_role: 'admin',
          tenant_id: 'tenant-1',
          read: false,
          created_at: readAt,
        });
      }
      await batch.commit();
    });

    const db = adminCtx(testEnv).firestore();
    const markAll = db.batch();
    for (const id of ids) {
      markAll.update(db.collection('notifications').doc(id), {
        read: true,
        read_at: firebase.firestore.FieldValue.serverTimestamp(),
      });
    }

    await assertSucceeds(markAll.commit());
  });

  it('notification readers cannot reset read state or partially/malform mark-read', async () => {
    await seedUser('admin-uid', 'admin');
    const readAt = firebase.firestore.Timestamp.now();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('notifications').doc('already-read').set({
        target_role: 'admin',
        tenant_id: 'tenant-1',
        read: true,
        read_at: readAt,
        created_at: readAt,
      });
      for (const id of [
        'unread-one',
        'unread-two',
        'unread-three',
        'unread-client-timestamp',
      ]) {
        await db.collection('notifications').doc(id).set({
          target_role: 'admin',
          tenant_id: 'tenant-1',
          read: false,
          created_at: readAt,
        });
      }
    });

    const db = adminCtx(testEnv).firestore();
    const notifications = db.collection('notifications');

    await assertFails(
      notifications.doc('already-read').update({
        read: false,
        read_at: firebase.firestore.Timestamp.now(),
      }),
    );
    await assertFails(
      notifications.doc('unread-one').update({ read: true }),
    );
    await assertFails(
      notifications.doc('unread-two').update({
        read_at: firebase.firestore.Timestamp.now(),
      }),
    );
    await assertFails(
      notifications.doc('unread-three').update({
        read_at: 'not-a-timestamp',
      }),
    );
    await assertFails(
      notifications.doc('unread-client-timestamp').update({
        read: true,
        read_at: firebase.firestore.Timestamp.now(),
      }),
    );
  });

  it('notification reads and updates require an active concrete tenant', async () => {
    await seedUser('global-notification-admin', 'admin', true, {
      tenant_id: null,
    });
    await seedUser('inactive-notification-admin', 'admin', false);
    await seedUser('inactive-tenant-notification-admin', 'admin');
    const readAt = firebase.firestore.Timestamp.now();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('notifications').doc('global-notification').set({
        target_role: 'admin',
        tenant_id: '__global__',
        read: false,
        created_at: readAt,
      });
      for (const id of [
        'inactive-user-notification',
        'inactive-tenant-notification',
      ]) {
        await db.collection('notifications').doc(id).set({
          target_role: 'admin',
          tenant_id: 'tenant-1',
          read: false,
          created_at: readAt,
        });
      }
      await db.collection('tenants').doc('tenant-1').update({
        active: false,
      });
    });

    const globalDb = testEnv.authenticatedContext(
      'global-notification-admin',
    ).firestore();
    const globalQuery = globalDb.collection('notifications')
      .where('tenant_id', '==', '__global__')
      .where('target_role', '==', 'admin')
      .orderBy('created_at', 'desc');
    await assertFails(globalQuery.get());
    await assertFails(
      globalDb.collection('notifications').doc('global-notification').update({
        read: true,
        read_at: firebase.firestore.Timestamp.now(),
      }),
    );

    const inactiveUserDb = testEnv.authenticatedContext(
      'inactive-notification-admin',
    ).firestore();
    await assertFails(
      inactiveUserDb.collection('notifications')
        .where('tenant_id', '==', 'tenant-1')
        .where('target_role', '==', 'admin')
        .orderBy('created_at', 'desc')
        .get(),
    );
    await assertFails(
      inactiveUserDb.collection('notifications')
        .doc('inactive-user-notification')
        .update({
          read: true,
          read_at: firebase.firestore.Timestamp.now(),
        }),
    );

    const inactiveTenantDb = adminCtx(testEnv).firestore();
    await assertFails(
      inactiveTenantDb.collection('notifications')
        .where('tenant_id', '==', 'tenant-1')
        .where('target_role', '==', 'admin')
        .orderBy('created_at', 'desc')
        .get(),
    );
    await assertFails(
      inactiveTenantDb.collection('notifications')
        .doc('inactive-tenant-notification')
        .update({
          read: true,
          read_at: firebase.firestore.Timestamp.now(),
        }),
    );
  });

  it('supervisor can query and mark admin-feed notifications in its tenant only', async () => {
    await seedUser('supervisor-uid', 'supervisor');
    await seedUser('other-admin-uid', 'admin', true, {
      tenant_id: 'tenant-2',
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('notifications').doc('tenant-notification').set({
        target_role: 'admin',
        tenant_id: 'tenant-1',
        read: false,
        created_at: firebase.firestore.Timestamp.now(),
      });
      await db.collection('notifications').doc('other-tenant').set({
        target_role: 'admin',
        tenant_id: 'tenant-2',
        read: false,
        created_at: firebase.firestore.Timestamp.now(),
      });
    });

    const db = supervisorCtx(testEnv).firestore();
    const snapshot = await assertSucceeds(
      db.collection('notifications')
        .where('tenant_id', '==', 'tenant-1')
        .where('target_role', '==', 'admin')
        .orderBy('created_at', 'desc')
        .limit(50)
        .get(),
    );
    assert.deepStrictEqual(
      snapshot.docs.map((doc) => doc.id),
      ['tenant-notification'],
    );
    await assertSucceeds(
      db.collection('notifications').doc('tenant-notification').update({
        read: true,
        read_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertFails(
      db.collection('notifications')
        .where('tenant_id', '==', 'tenant-2')
        .where('target_role', '==', 'admin')
        .orderBy('created_at', 'desc')
        .limit(50)
        .get(),
    );
    await assertFails(
      db.collection('notifications').doc('other-tenant').update({
        read: true,
        read_at: firebase.firestore.Timestamp.now(),
      }),
    );
  });

  it('seller cannot query or update the admin notification feed', async () => {
    await seedUser('seller-uid', 'seller');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection('notifications').doc('tenant-notification').set({
        target_role: 'admin',
        tenant_id: 'tenant-1',
        read: false,
        created_at: firebase.firestore.Timestamp.now(),
      });
    });

    const db = sellerCtx(testEnv).firestore();
    await assertFails(
      db.collection('notifications')
        .where('tenant_id', '==', 'tenant-1')
        .where('target_role', '==', 'admin')
        .orderBy('created_at', 'desc')
        .limit(50)
        .get(),
    );
    await assertFails(
      db.collection('notifications').doc('tenant-notification').update({
        read: true,
        read_at: firebase.firestore.Timestamp.now(),
      }),
    );
  });

  it('seller cash receipt notifications must link to the matching receipt', async () => {
    await seedUser('seller-uid', 'seller');
    await seedUser('admin-uid', 'admin');
    await seedShop('shop-1');
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('invoices').doc('receipt-1').set({
        tenant_id: 'tenant-1',
        type: 'cash_receipt',
        created_by: 'seller-uid',
        seller_id: 'seller-uid',
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        invoice_number: 'REC-2026-0001',
        total: 125,
      });
    });

    const db = sellerCtx(testEnv).firestore();
    const notification = {
      type: 'invoice',
      shop_id: 'shop-1',
      shop_name: 'Seed Shop',
      route_id: 'route-1',
      seller_id: 'seller-uid',
      seller_name: 'Test User',
      amount: 125,
      transaction_type: 'cash_in',
      invoice_number: 'REC-2026-0001',
      ref_id: 'receipt-1',
      target_role: 'admin',
      read: false,
      tenant_id: 'tenant-1',
      created_by: 'seller-uid',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    };
    await assertSucceeds(
      db.collection('notifications').doc('invoice_receipt-1').set(notification),
    );
    await assertFails(
      db.collection('notifications').doc('invoice_wrong-type').set({
        ...notification,
        transaction_type: 'cash_out',
      }),
    );
    await assertSucceeds(
      adminCtx(testEnv).firestore()
        .collection('notifications')
        .doc('invoice_receipt-1')
        .get(),
    );
  });

  it('notification role and tenant boundaries hold across 15 workspaces', async () => {
    const roles = [
      'admin',
      'manager',
      'tenant_admin',
      'supervisor',
      'seller',
    ];
    const fixtures = [];

    for (let index = 0; index < 15; index += 1) {
      const tenantId = `notification-workspace-${index + 1}`;
      const uid = `notification-user-${index + 1}`;
      const role = roles[index % roles.length];
      const notificationId = `notification-${index + 1}`;
      fixtures.push({ tenantId, uid, role, notificationId });
      await seedUser(uid, role, true, { tenant_id: tenantId });
    }

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const fixture of fixtures) {
        await db.collection('notifications').doc(fixture.notificationId).set({
          target_role: 'admin',
          tenant_id: fixture.tenantId,
          read: false,
          created_at: firebase.firestore.Timestamp.now(),
        });
      }
    });

    for (let index = 0; index < fixtures.length; index += 1) {
      const fixture = fixtures[index];
      const otherTenantId = fixtures[(index + 1) % fixtures.length].tenantId;
      const db = testEnv.authenticatedContext(fixture.uid).firestore();
      const scopedQuery = (tenantId) => db.collection('notifications')
        .where('tenant_id', '==', tenantId)
        .where('target_role', '==', 'admin')
        .orderBy('created_at', 'desc')
        .limit(50);

      if (fixture.role === 'seller') {
        await assertFails(scopedQuery(fixture.tenantId).get());
        await assertFails(
          db.collection('notifications').doc(fixture.notificationId).update({
            read: true,
            read_at: firebase.firestore.FieldValue.serverTimestamp(),
          }),
        );
      } else {
        const snapshot = await assertSucceeds(
          scopedQuery(fixture.tenantId).get(),
        );
        assert.deepStrictEqual(
          snapshot.docs.map((doc) => doc.id),
          [fixture.notificationId],
        );
        await assertSucceeds(
          db.collection('notifications').doc(fixture.notificationId).update({
            read: true,
            read_at: firebase.firestore.FieldValue.serverTimestamp(),
          }),
        );
      }
      await assertFails(scopedQuery(otherTenantId).get());
    }

    const selectedWorkspace = 'notification-platform-workspace';
    await seedUser('platform-notification-uid', 'super_admin', true, {
      active_workspace_id: selectedWorkspace,
      active_workspace_reason: 'Investigate notification access',
      active_workspace_selected_at: new Date(),
      tenant_id: selectedWorkspace,
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('notifications')
        .doc('platform-notification')
        .set({
          target_role: 'admin',
          tenant_id: selectedWorkspace,
          read: false,
          created_at: firebase.firestore.Timestamp.now(),
        });
    });
    const platformDb = testEnv.authenticatedContext(
      'platform-notification-uid',
    ).firestore();
    const platformFeed = (tenantId) => platformDb.collection('notifications')
      .where('tenant_id', '==', tenantId)
      .where('target_role', '==', 'admin')
      .orderBy('created_at', 'desc')
      .limit(50);

    await assertFails(platformFeed(selectedWorkspace).get());
    await assertFails(
      platformFeed(fixtures[0].tenantId).get(),
    );
    await assertFails(
      platformDb.collection('notifications')
        .doc('platform-notification')
        .update({
          read: true,
          read_at: firebase.firestore.Timestamp.now(),
        }),
    );
  });

  it('seller: cannot create a notification without a matching source', async () => {
    await seedUser('seller-uid', 'seller');
    const db = sellerCtx(testEnv).firestore();
    await assertFails(
      db.collection('notifications').doc('n1').set({
        created_by: 'seller-uid',
        tenant_id: 'tenant-1',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    await assertFails(
      db.collection('users').doc('seller-uid').update({
        last_notification_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
  });

  it('seller: can notify for each persisted transaction without a cooldown', async () => {
    await seedUser('seller-uid', 'seller');
    await seedShop('shop-1', { balance: 100 });
    const db = sellerCtx(testEnv).firestore();
    const shopRef = db.collection('customers').doc('shop-1');
    const entries = [
      { id: 'tx-one', type: 'cash_out', amount: 25, balance: 125 },
      { id: 'tx-two', type: 'cash_in', amount: 5, balance: 120 },
    ];

    for (const entry of entries) {
      const txRef = db.collection('transactions').doc(entry.id);
      const batch = db.batch();
      batch.set(txRef, {
        shop_id: 'shop-1',
        customer_id: 'shop-1',
        shop_name: 'Shop One',
        route_id: 'route-1',
        tenant_id: 'tenant-1',
        type: entry.type,
        amount: entry.amount,
        description: 'Standalone cash transaction',
        created_by: 'seller-uid',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
        deleted: false,
      });
      batch.update(shopRef, {
        balance: entry.balance,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
        last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
        last_transaction_type: entry.type,
        last_transaction_amount: entry.amount,
        last_transaction_id: txRef.id,
      });
      await assertSucceeds(batch.commit());
      await assertSucceeds(
        db.collection('notifications').doc(`transaction_${txRef.id}`).set({
          type: 'transaction',
          shop_id: 'shop-1',
          shop_name: 'Shop One',
          route_id: 'route-1',
          seller_id: 'seller-uid',
          seller_name: 'Test User',
          amount: entry.amount,
          transaction_type: entry.type,
          ref_id: txRef.id,
          target_role: 'admin',
          read: false,
          tenant_id: 'tenant-1',
          created_by: 'seller-uid',
          created_at: firebase.firestore.FieldValue.serverTimestamp(),
        }),
      );
    }

    const txRef = db.collection('transactions').doc('tx-mismatched-notif');
    const mismatchedBatch = db.batch();
    mismatchedBatch.set(txRef, {
      shop_id: 'shop-1',
      customer_id: 'shop-1',
      shop_name: 'Shop One',
      route_id: 'route-1',
      tenant_id: 'tenant-1',
      type: 'cash_out',
      amount: 10,
      description: 'Standalone cash transaction',
      created_by: 'seller-uid',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
      deleted: false,
    });
    mismatchedBatch.update(shopRef, {
      balance: 130,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_at: firebase.firestore.FieldValue.serverTimestamp(),
      last_transaction_type: 'cash_out',
      last_transaction_amount: 10,
      last_transaction_id: txRef.id,
    });
    await assertSucceeds(mismatchedBatch.commit());
    await assertFails(
      db.collection('notifications').doc(`transaction_${txRef.id}`).set({
        type: 'transaction',
        shop_id: 'shop-1',
        shop_name: 'Shop One',
        route_id: 'route-1',
        seller_id: 'seller-uid',
        seller_name: 'Test User',
        amount: 999,
        transaction_type: 'cash_out',
        ref_id: txRef.id,
        target_role: 'admin',
        read: false,
        tenant_id: 'tenant-1',
        created_by: 'seller-uid',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );
    const shopAfterNotificationFailure = await assertSucceeds(shopRef.get());
    assert.strictEqual(shopAfterNotificationFailure.data().balance, 130);
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
      active_workspace_access_log_id: logRef.id,
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

  it('workspace selection can atomically end the old context and start the new one', async () => {
    await seedWorkspace('tenant-a');
    await seedWorkspace('tenant-b');
    const previousSelectedAt = new Date();
    await seedUser('platform-switch-workspace-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Previous support review',
      active_workspace_selected_at: previousSelectedAt,
      active_workspace_access_log_id: 'previous-start',
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('platform_access_logs')
        .doc('previous-start')
        .set({
          actor_user_id: 'platform-switch-workspace-uid',
          workspace_id: 'tenant-a',
          event_type: 'workspace_access_started',
          reason: 'Previous support review',
          created_at: previousSelectedAt,
        });
    });

    const db = testEnv.authenticatedContext(
      'platform-switch-workspace-uid',
    ).firestore();
    const batch = db.batch();
    const userRef = db.collection('users').doc('platform-switch-workspace-uid');
    const endedLogRef = db.collection('platform_access_logs').doc('switch-end');
    const startedLogRef = db.collection('platform_access_logs').doc('switch-start');
    batch.update(userRef, {
      active_workspace_id: 'tenant-b',
      active_workspace_reason: 'New support request',
      active_workspace_selected_at:
        firebase.firestore.FieldValue.serverTimestamp(),
      active_workspace_access_log_id: startedLogRef.id,
      last_workspace_access_end_log_id: endedLogRef.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(endedLogRef, {
      actor_user_id: 'platform-switch-workspace-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_ended',
      reason: 'Previous support review',
      started_log_id: 'previous-start',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    batch.set(startedLogRef, {
      actor_user_id: 'platform-switch-workspace-uid',
      workspace_id: 'tenant-b',
      event_type: 'workspace_access_started',
      reason: 'New support request',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });

    await assertSucceeds(batch.commit());
    const endedLog = await db.collection('platform_access_logs')
      .doc('switch-end')
      .get();
    const startedLog = await db.collection('platform_access_logs')
      .doc('switch-start')
      .get();
    assert.strictEqual(endedLog.data().event_type, 'workspace_access_ended');
    assert.strictEqual(startedLog.data().event_type, 'workspace_access_started');
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

  it('workspace selection atomically links its support access audit log', async () => {
    await seedWorkspace('tenant-a');
    await seedUser('platform-select-payload-uid', 'super_admin');
    const db = testEnv.authenticatedContext('platform-select-payload-uid').firestore();
    const batch = db.batch();
    const logRef = db.collection('platform_access_logs').doc('start-log');
    batch.update(db.collection('users').doc('platform-select-payload-uid'), {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: firebase.firestore.FieldValue.serverTimestamp(),
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

    const mismatchedBatch = db.batch();
    const mismatchedLogRef = db.collection('platform_access_logs')
      .doc('end-log-mismatched');
    mismatchedBatch.update(
      db.collection('users').doc('platform-exit-payload-uid'),
      {
        active_workspace_id: firebase.firestore.FieldValue.delete(),
        active_workspace_reason: firebase.firestore.FieldValue.delete(),
        active_workspace_selected_at: firebase.firestore.FieldValue.delete(),
        active_workspace_access_log_id: firebase.firestore.FieldValue.delete(),
        last_workspace_access_end_log_id: mismatchedLogRef.id,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      },
    );
    mismatchedBatch.set(mismatchedLogRef, {
      actor_user_id: 'platform-exit-payload-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_ended',
      reason: 'Support ticket investigation',
      started_log_id: 'another-start-log',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertFails(mismatchedBatch.commit());

    const allowedBatch = db.batch();
    const allowedLogRef = db.collection('platform_access_logs').doc('start-log-allowed');
    allowedBatch.update(db.collection('users').doc('platform-select-payload-uid'), {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: firebase.firestore.FieldValue.serverTimestamp(),
      active_workspace_access_log_id: allowedLogRef.id,
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
    const selectedAt = new Date();
    await seedUser('platform-exit-payload-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: selectedAt,
      active_workspace_access_log_id: 'start-log',
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('platform_access_logs')
        .doc('start-log')
        .set({
          actor_user_id: 'platform-exit-payload-uid',
          workspace_id: 'tenant-a',
          event_type: 'workspace_access_started',
          reason: 'Support ticket investigation',
          created_at: selectedAt,
        });
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
      started_log_id: 'start-log',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertFails(batch.commit());

    const allowedBatch = db.batch();
    const allowedLogRef = db.collection('platform_access_logs').doc('end-log-allowed');
    allowedBatch.update(db.collection('users').doc('platform-exit-payload-uid'), {
      active_workspace_id: firebase.firestore.FieldValue.delete(),
      active_workspace_reason: firebase.firestore.FieldValue.delete(),
      active_workspace_selected_at: firebase.firestore.FieldValue.delete(),
      active_workspace_access_log_id: firebase.firestore.FieldValue.delete(),
      last_workspace_access_end_log_id: allowedLogRef.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    allowedBatch.set(allowedLogRef, {
      actor_user_id: 'platform-exit-payload-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_ended',
      reason: 'Support ticket investigation',
      started_log_id: 'start-log',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(allowedBatch.commit());
  });

  it('requires an end audit event when a super-admin clears support context', async () => {
    await seedWorkspace('tenant-a');
    const selectedAt = new Date();
    await seedUser('platform-unlogged-exit-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: selectedAt,
      active_workspace_access_log_id: 'start-log',
    });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('platform_access_logs')
        .doc('start-log')
        .set({
          actor_user_id: 'platform-unlogged-exit-uid',
          workspace_id: 'tenant-a',
          event_type: 'workspace_access_started',
          reason: 'Support ticket investigation',
          created_at: selectedAt,
        });
    });
    const db = testEnv.authenticatedContext(
      'platform-unlogged-exit-uid',
    ).firestore();

    await assertFails(
      db.collection('users').doc('platform-unlogged-exit-uid').update({
        active_workspace_id: firebase.firestore.FieldValue.delete(),
        active_workspace_reason: firebase.firestore.FieldValue.delete(),
        active_workspace_selected_at: firebase.firestore.FieldValue.delete(),
        active_workspace_access_log_id: firebase.firestore.FieldValue.delete(),
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      }),
    );

    const endLogRef = db.collection('platform_access_logs').doc('end-log');
    const endingBatch = db.batch();
    endingBatch.update(
      db.collection('users').doc('platform-unlogged-exit-uid'),
      {
        active_workspace_id: firebase.firestore.FieldValue.delete(),
        active_workspace_reason: firebase.firestore.FieldValue.delete(),
        active_workspace_selected_at: firebase.firestore.FieldValue.delete(),
        active_workspace_access_log_id: firebase.firestore.FieldValue.delete(),
        last_workspace_access_end_log_id: endLogRef.id,
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
      },
    );
    endingBatch.set(endLogRef, {
      actor_user_id: 'platform-unlogged-exit-uid',
      workspace_id: 'tenant-a',
      event_type: 'workspace_access_ended',
      reason: 'Support ticket investigation',
      started_log_id: 'start-log',
      created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(endingBatch.commit());
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

  it('future-dated workspace selection cannot read tenant business data', async () => {
    await seedWorkspace('tenant-a');
    await seedBusinessCollections(['tenant-a']);
    await seedUser('platform-future-uid', 'super_admin', true, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at: new Date(Date.now() + 60 * 60 * 1000),
    });
    const db = testEnv.authenticatedContext('platform-future-uid').firestore();

    await assertFails(
      db.collection('products').where('tenant_id', '==', 'tenant-a').get(),
    );
    await assertFails(
      db.collection('invoices').doc('future-missing-invoice').get(),
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

  it('platform user creation writes canonical roles while legacy manager stays read-compatible', async () => {
    await seedTenant();
    await seedUser('platform-canonical-role-writer', 'super_admin', true, {
      active_workspace_id: 'tenant-1',
      active_workspace_reason: 'Canonical role write verification',
      active_workspace_selected_at: new Date(),
    });
    const db = testEnv
      .authenticatedContext('platform-canonical-role-writer')
      .firestore();

    await assertFails(
      createUserWithSeat(db, 'new-manager-alias', {
        role: 'manager',
        createdBy: 'platform-canonical-role-writer',
        assignedRouteIds: [],
      }),
    );
    await assertSucceeds(
      createUserWithSeat(db, 'new-canonical-admin', {
        role: 'admin',
        createdBy: 'platform-canonical-role-writer',
        assignedRouteIds: [],
      }),
    );
    await assertFails(
      db.collection('users').doc('new-canonical-admin').update({
        role: 'manager',
        updated_at: firebase.firestore.FieldValue.serverTimestamp(),
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
    const accessBatch = platformDb.batch();
    const userRef = platformDb.collection('users').doc('platform-audit-uid');
    const accessLogRef = platformDb.collection('platform_access_logs').doc('log-1');
    accessBatch.update(userRef, {
      active_workspace_id: 'tenant-a',
      active_workspace_reason: 'Support ticket investigation',
      active_workspace_selected_at:
        firebase.firestore.FieldValue.serverTimestamp(),
      active_workspace_access_log_id: accessLogRef.id,
      updated_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    accessBatch.set(accessLogRef, {
        actor_user_id: 'platform-audit-uid',
        workspace_id: 'tenant-a',
        event_type: 'workspace_access_started',
        reason: 'Support ticket investigation',
        created_at: firebase.firestore.FieldValue.serverTimestamp(),
    });
    await assertSucceeds(accessBatch.commit());
    await assertFails(
      platformDb.collection('platform_access_logs').doc('orphan-log').set({
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

  async function seedSale({
    role,
    uid,
    lineCount = 1,
    lastInvoiceNumber = 0,
    lastCashReceiptNumber = 0,
    allowNonStockInvoices = false,
  }) {
    await seedTenant();
    await seedUser(uid, role, true, { assigned_route_ids: ['route-1'] });
    await seedShop('shop-1', { balance: 0 });
    await seedSettings({
      company_name: 'Acme Footwear',
      invoice_header: { show_phone: true },
      logo_base64: null,
      last_invoice_number: lastInvoiceNumber,
      last_cash_receipt_number: lastCashReceiptNumber,
      ...(allowNonStockInvoices ? { allow_non_stock_invoices: true } : {}),
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

  function saleTransaction(
    db,
    uid,
    {
      lineCount = 1,
      amountReceived = 0,
      fulfillmentMode = 'stock',
      includeFinancialMinorUnits = false,
    } = {},
  ) {
    const settingsRef = db.collection('settings').doc('tenant-1');
    const shopRef = db.collection('customers').doc('shop-1');
    const invoiceRef = db.collection('invoices').doc('invoice-client-shape');
    const saleRef = db.collection('transactions').doc('sale-client-shape');
    const paymentRef = db.collection('transactions').doc('payment-client-shape');
    const inventoryRefs = fulfillmentMode == 'stock'
      ? Array.from({ length: lineCount }, (_, index) =>
          db.collection('seller_inventory').doc(`inventory-${index + 1}`),
        )
      : [];
    const total = lineCount * 100;
    const items = Array.from({ length: lineCount }, (_, index) => ({
      variant_id: `variant-${index + 1}`,
      qty: 1,
      unit_price: 100,
      ...(includeFinancialMinorUnits ? { subtotal: 100 } : {}),
    }));
    const itemMinorUnits = Object.fromEntries(
      items.flatMap((item, index) => [
        [`items.${index}.unit_price`, 10000],
        ...(includeFinancialMinorUnits
          ? [[`items.${index}.subtotal`, 10000]]
          : []),
      ]),
    );

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
      const settingsData = settingsSnapshot.data();
      const invoiceSequence = Math.max(
        settingsData.last_invoice_number ?? 0,
        settingsData.last_cash_receipt_number ?? 0,
      ) + 1;
      const invoiceNumber = `INV-${String(invoiceSequence).padStart(4, '0')}`;
      transaction.update(settingsRef, {
        last_invoice_number: invoiceSequence,
        last_invoice_id: invoiceRef.id,
      });
      transaction.set(invoiceRef, {
        tenant_id: 'tenant-1',
        invoice_number: invoiceNumber,
        invoice_sequence: invoiceSequence,
        sale_transaction_id: saleRef.id,
        idempotency_key: 'client-shape-key',
        type: 'sale',
        fulfillment_mode: fulfillmentMode,
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
        seller_inventory_deductions: fulfillmentMode == 'stock'
          ? Object.fromEntries(inventoryRefs.map((ref) => [ref.id, 1]))
          : {},
        created_by: uid,
        created_at: now,
        updated_at: now,
        ...(includeFinancialMinorUnits
          ? {
              financial_minor_units: {
                subtotal: total * 100,
                discount: 0,
                total: total * 100,
                amount_received: amountReceived * 100,
                outstanding_amount: (total - amountReceived) * 100,
                ...itemMinorUnits,
              },
            }
          : {}),
      });
      transaction.set(saleRef, {
        tenant_id: 'tenant-1',
        shop_id: 'shop-1',
        shop_name: 'Seed Shop',
        route_id: 'route-1',
        type: 'cash_out',
        sale_type: amountReceived >= total ? 'cash' : 'credit',
        amount: total,
        description: `Invoice ${invoiceNumber}`,
        items,
        invoice_id: invoiceRef.id,
        invoice_number: invoiceNumber,
        created_by: uid,
        created_at: now,
        deleted: false,
        ...(includeFinancialMinorUnits
          ? {
              financial_minor_units: {
                amount: total * 100,
                ...itemMinorUnits,
              },
            }
          : {}),
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
          description: `Payment for ${invoiceNumber}`,
          items: [],
          invoice_id: invoiceRef.id,
          invoice_number: invoiceNumber,
          created_by: uid,
          created_at: now,
          deleted: false,
          ...(includeFinancialMinorUnits
            ? { financial_minor_units: { amount: amountReceived * 100 } }
            : {}),
        });
      }
      transaction.update(shopRef, {
        balance: firebase.firestore.FieldValue.increment(total - amountReceived),
        updated_at: now,
        last_transaction_at: now,
        last_transaction_type: 'cash_out',
        last_transaction_amount: total,
        last_transaction_id: saleRef.id,
        ...(includeFinancialMinorUnits
          ? {
              financial_minor_units: {
                balance: (total - amountReceived) * 100,
                last_transaction_amount: total * 100,
              },
            }
          : {}),
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

  it('seller sale sequence continues after a higher cash receipt counter', async () => {
    await seedSale({
      role: 'seller',
      uid: 'seller-uid',
      lastCashReceiptNumber: 4,
    });
    const db = sellerCtx(testEnv).firestore();
    await assertSucceeds(saleTransaction(db, 'seller-uid'));
    const invoice = await db.collection('invoices')
      .doc('invoice-client-shape').get();
    assert.strictEqual(invoice.data().invoice_sequence, 5);
    assert.strictEqual(invoice.data().invoice_number, 'INV-0005');
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

  it('tenant admin can create a non-stock sale in a provider-shaped transaction', async () => {
    await seedSale({
      role: 'tenant_admin',
      uid: 'tenant-admin-uid',
      allowNonStockInvoices: true,
    });
    await assertSucceeds(saleTransaction(
      tenantAdminCtx(testEnv).firestore(),
      'tenant-admin-uid',
      {
        fulfillmentMode: 'non_stock',
        includeFinancialMinorUnits: true,
      },
    ));
  });

  it('admin can create the first non-stock sale after a prior receipt sequence', async () => {
    await seedSale({
      role: 'admin',
      uid: 'admin-uid',
      lastCashReceiptNumber: 1,
      allowNonStockInvoices: true,
    });
    await assertSucceeds(saleTransaction(
      adminCtx(testEnv).firestore(),
      'admin-uid',
      { fulfillmentMode: 'non_stock' },
    ));
  });

  it('tenant admin cannot create a non-stock sale when the workspace disables it', async () => {
    await seedSale({
      role: 'tenant_admin',
      uid: 'tenant-admin-uid',
    });
    await assertFails(saleTransaction(
      tenantAdminCtx(testEnv).firestore(),
      'tenant-admin-uid',
      {
        fulfillmentMode: 'non_stock',
        includeFinancialMinorUnits: true,
      },
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

  it('seller four-line stock sale with payment stays within the Rules access budget', async () => {
    await seedSale({ role: 'seller', uid: 'seller-uid', lineCount: 4 });
    await assertSucceeds(saleTransaction(
      sellerCtx(testEnv).firestore(),
      'seller-uid',
      { lineCount: 4, amountReceived: 40 },
    ));
  });

  it('seller stock sales with 5 to 30 lines stay within the Rules access budget', async () => {
    for (const lineCount of [5, 10, 15, 20, 30]) {
      await testEnv.clearFirestore();
      await seedSale({ role: 'seller', uid: 'seller-uid', lineCount });
      await assertSucceeds(saleTransaction(
        sellerCtx(testEnv).firestore(),
        'seller-uid',
        { lineCount, amountReceived: 40 },
      ));
    }
  });
});
