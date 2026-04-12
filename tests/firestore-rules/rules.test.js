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
async function seedUser(uid, role, active = true) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({
      role,
      active,
      display_name: 'Test User',
      email: `${uid}@test.com`,
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
});
