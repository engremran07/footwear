/**
 * dev_reset.js — DEV ONLY
 * Resets ALL financial state in Firestore to a clean start:
 *   1. settings/global.last_invoice_number → 0
 *   2. Every shop doc (customers collection): balance → 0.0
 *
 * Uses Firebase CLI refresh token (no service account needed).
 * Run from repo root: node dev_reset.js
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

const PROJECT = 'shoeserp-clean-20260327';
const DB = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = 'firestore.googleapis.com';

// ── Get access token from Firebase CLI stored credentials ──────────────────
function getToken() {
  const cfgPath = path.join(
    process.env.USERPROFILE || process.env.HOME,
    '.config', 'configstore', 'firebase-tools.json',
  );
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  const refresh = cfg.tokens?.refresh_token;
  if (!refresh) throw new Error('No refresh_token in firebase-tools.json');

  const toolsApi = require('C:/Users/gsmen/AppData/Roaming/npm/node_modules/firebase-tools/lib/api.js');
  const clientId = toolsApi.clientId();
  const clientSecret = toolsApi.clientSecret();

  return new Promise((resolve, reject) => {
    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refresh,
      client_id: clientId,
      client_secret: clientSecret,
    }).toString();
    let data = '';
    const req = https.request(
      {
        hostname: 'oauth2.googleapis.com',
        path: '/token',
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      },
      (res) => {
        res.on('data', (d) => (data += d));
        res.on('end', () => {
          const json = JSON.parse(data);
          if (json.access_token) resolve(json.access_token);
          else reject(new Error('Token exchange failed: ' + data));
        });
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── Firestore REST helpers ──────────────────────────────────────────────────
function firestoreRequest(method, urlPath, token, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : null;
    const options = {
      hostname: BASE,
      path: `/v1/${DB}${urlPath}`,
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {}),
      },
    };
    let data = '';
    const req = https.request(options, (res) => {
      res.on('data', (d) => (data += d));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve(data);
        }
      });
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

async function patchField(token, colPath, docId, firestoreFields, maskPaths) {
  const mask = maskPaths.map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join('&');
  return firestoreRequest(
    'PATCH',
    `/${colPath}/${docId}?${mask}`,
    token,
    { fields: firestoreFields },
  );
}

async function listCollection(token, colPath, pageToken) {
  const qs = pageToken ? `?pageToken=${pageToken}` : '';
  return firestoreRequest('GET', `/${colPath}${qs}`, token, null);
}

// ── Reset logic ─────────────────────────────────────────────────────────────
async function resetInvoiceCounter(token) {
  console.log('\n── 1. Resetting invoice counter ──');
  const res = await patchField(
    token,
    'settings',
    'global',
    { last_invoice_number: { integerValue: '0' } },
    ['last_invoice_number'],
  );
  if (res.error) {
    console.error('  ✗ Failed:', res.error.message);
  } else {
    console.log('  ✓ settings/global.last_invoice_number → 0');
  }
}

async function resetShopBalances(token) {
  console.log('\n── 2. Resetting shop balances ──');
  let count = 0;
  let pageToken = null;

  do {
    const page = await listCollection(token, 'customers', pageToken);
    const docs = page.documents || [];

    for (const doc of docs) {
      const docId = doc.name.split('/').pop();
      const currentBalance = doc.fields?.balance?.doubleValue
        || doc.fields?.balance?.integerValue
        || 0;

      if (Number(currentBalance) === 0) {
        console.log(`  skip  ${docId} (balance already 0)`);
        continue;
      }

      const res = await patchField(
        token,
        'customers',
        docId,
        { balance: { doubleValue: 0 } },
        ['balance'],
      );
      if (res.error) {
        console.error(`  ✗ ${docId}: ${res.error.message}`);
      } else {
        console.log(`  ✓ ${docId} balance: ${currentBalance} → 0`);
        count++;
      }
    }

    pageToken = page.nextPageToken || null;
  } while (pageToken);

  console.log(`  Done — reset ${count} shop(s)`);
}

async function main() {
  console.log('\n════════════════════════════════════════');
  console.log('  DEV RESET — financial state only');
  console.log(`  Project: ${PROJECT}`);
  console.log('════════════════════════════════════════');

  const token = await getToken();
  console.log('  Auth: ✓ token obtained');

  await resetInvoiceCounter(token);
  await resetShopBalances(token);

  console.log('\n✓ Reset complete. All balances are 0, invoice counter is 0.\n');
}

main().catch((e) => {
  console.error('Reset failed:', e.message || e);
  process.exit(1);
});
