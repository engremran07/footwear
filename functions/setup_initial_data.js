/**
 * One-time setup script: creates admin user + all seed Firestore documents.
 * Run from functions/ folder:  node setup_initial_data.js
 * Delete this file after running.
 */

const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

// Uses Application Default Credentials (firebase CLI login already authenticated)
initializeApp({ projectId: 'footwear-erp-a3e63' });

const auth = getAuth();
const db = getFirestore();

const ADMIN_EMAIL = 'admin@footwearerp.com';
const ADMIN_PASSWORD = 'Admin@12345';
const ADMIN_NAME = 'Admin';

async function run() {
  console.log('=== ShoesERP Initial Setup ===\n');

  // ── 1. Create Firebase Auth user ─────────────────────────────────────────
  let uid;
  try {
    const existing = await auth.getUserByEmail(ADMIN_EMAIL);
    uid = existing.uid;
    console.log(`✓ Auth user already exists: ${ADMIN_EMAIL} (${uid})`);
  } catch {
    const user = await auth.createUser({
      email: ADMIN_EMAIL,
      password: ADMIN_PASSWORD,
      displayName: ADMIN_NAME,
      emailVerified: true,
    });
    uid = user.uid;
    console.log(`✓ Created Auth user: ${ADMIN_EMAIL} (${uid})`);
  }

  const now = Timestamp.now();

  // ── 2. Create users/{uid} document ───────────────────────────────────────
  await db.collection('users').doc(uid).set({
    email: ADMIN_EMAIL,
    display_name: ADMIN_NAME,
    role: 'admin',
    worker_id: null,
    active: true,
    created_at: now,
    updated_at: now,
  }, { merge: true });
  console.log(`✓ Firestore users/${uid} created (role: admin)`);

  // ── 3. Create settings/global ─────────────────────────────────────────────
  await db.collection('settings').doc('global').set({
    company_name: 'Footwear ERP',
    currency_primary: 'SAR',
    currency_secondary: 'PKR',
    tax_rate: 0.0,
    low_stock_threshold: 10,
    logo_url: null,
    updated_at: now,
  }, { merge: true });
  console.log('✓ Firestore settings/global created');

  // ── 4. Create pnl_snapshots for current month ─────────────────────────────
  const period = new Date().toISOString().slice(0, 7); // YYYY-MM
  await db.collection('pnl_snapshots').doc(period).set({
    id: period,
    period,
    revenue: 0.0,
    cogs: 0.0,
    gross_profit: 0.0,
    expenses: 0.0,
    worker_cost: 0.0,
    net_profit: 0.0,
    updated_at: now,
  }, { merge: true });
  console.log(`✓ Firestore pnl_snapshots/${period} seeded`);

  console.log('\n=== Setup Complete ===');
  console.log(`\nAdmin login credentials:`);
  console.log(`  Email:    ${ADMIN_EMAIL}`);
  console.log(`  Password: ${ADMIN_PASSWORD}`);
  console.log('\nChange the password after first login via Settings → Users.');
  process.exit(0);
}

run().catch(err => {
  console.error('Setup failed:', err.message);
  process.exit(1);
});
