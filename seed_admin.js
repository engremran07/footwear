/**
 * seed_admin.js
 * Creates admin user + required Firestore docs via Firebase REST APIs.
 * Run with: node seed_admin.js
 * No firebase-admin, no service account needed.
 */

const https = require('https');

const API_KEY     = 'AIzaSyAVT31GIOQ01IV4O1K7a7ysRhB8PEfQJXY';
const PROJECT_ID  = 'footwear-erp-a3e63';
const ADMIN_EMAIL = 'admin@footwear.erp';
const ADMIN_PASS  = 'Admin@12345!';
const ADMIN_NAME  = 'Admin';

function post(hostname, path, body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request({
      hostname, path, method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
    }, res => {
      let raw = '';
      res.on('data', c => raw += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(raw) }); }
        catch { resolve({ status: res.statusCode, body: raw }); }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function patch(hostname, path, body, token) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const headers = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) };
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const req = https.request({ hostname, path, method: 'PATCH', headers }, res => {
      let raw = '';
      res.on('data', c => raw += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(raw) }); }
        catch { resolve({ status: res.statusCode, body: raw }); }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function firestoreStr(v)  { return { stringValue: v }; }
function firestoreBool(v) { return { booleanValue: v }; }
function firestoreNum(v)  { return { doubleValue: v }; }
function firestoreInt(v)  { return { integerValue: String(v) }; }
function firestoreTs()    { return { timestampValue: new Date().toISOString() }; }

async function main() {
  console.log('=== Footwear ERP Seed Script ===\n');

  // 1. Create auth user
  console.log(`Creating user: ${ADMIN_EMAIL}`);
  const signUpRes = await post('identitytoolkit.googleapis.com',
    `/v1/accounts:signUp?key=${API_KEY}`,
    { email: ADMIN_EMAIL, password: ADMIN_PASS, displayName: ADMIN_NAME, returnSecureToken: true }
  );

  if (signUpRes.status !== 200) {
    const err = signUpRes.body?.error;
    if (err?.message === 'EMAIL_EXISTS') {
      console.log('User already exists — signing in to get UID...');
      const signInRes = await post('identitytoolkit.googleapis.com',
        `/v1/accounts:signInWithPassword?key=${API_KEY}`,
        { email: ADMIN_EMAIL, password: ADMIN_PASS, returnSecureToken: true }
      );
      if (signInRes.status !== 200) {
        console.error('Sign-in failed:', signInRes.body);
        process.exit(1);
      }
      var uid = signInRes.body.localId;
      var idToken = signInRes.body.idToken;
      console.log(`  Signed in — UID: ${uid}`);
    } else {
      console.error('Sign-up failed:', signUpRes.body);
      process.exit(1);
    }
  } else {
    var uid = signUpRes.body.localId;
    var idToken = signUpRes.body.idToken;
    console.log(`  Created — UID: ${uid}`);
  }

  const fsHost = 'firestore.googleapis.com';
  const fsBase = `/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

  // 2. Create users/{uid} doc
  console.log('\nCreating users document...');
  const userDocRes = await patch(fsHost, `${fsBase}/users/${uid}`, {
    fields: {
      email:        firestoreStr(ADMIN_EMAIL),
      display_name: firestoreStr(ADMIN_NAME),
      role:         firestoreStr('admin'),
      active:       firestoreBool(true),
      created_at:   firestoreTs(),
      updated_at:   firestoreTs(),
    }
  }, idToken);
  console.log(`  Status: ${userDocRes.status}`, userDocRes.status === 200 ? '✓' : JSON.stringify(userDocRes.body?.error || userDocRes.body));

  // 3. Create settings/global doc
  console.log('\nCreating settings/global document...');
  const settingsRes = await patch(fsHost, `${fsBase}/settings/global`, {
    fields: {
      company_name:        firestoreStr('Footwear ERP'),
      currency_primary:    firestoreStr('SAR'),
      currency_secondary:  firestoreStr('PKR'),
      tax_rate:            firestoreNum(0),
      low_stock_threshold: firestoreInt(10),
      updated_at:          firestoreTs(),
    }
  }, idToken);
  console.log(`  Status: ${settingsRes.status}`, settingsRes.status === 200 ? '✓' : JSON.stringify(settingsRes.body?.error || settingsRes.body));

  console.log('\n=== Done ===');
  console.log(`\nLogin credentials:`);
  console.log(`  Email:    ${ADMIN_EMAIL}`);
  console.log(`  Password: ${ADMIN_PASS}`);
  console.log(`  Role:     admin`);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
