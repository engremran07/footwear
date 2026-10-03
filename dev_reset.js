/**
 * dev_reset.js — DEV ONLY
 * Resets financial state for one explicitly selected development tenant.
 *
 * Uses Firebase CLI refresh token (no service account needed).
 * Requires FIREBASE_PROJECT_ID, ALLOWED_DEV_FIREBASE_PROJECT_ID, and
 * FIREBASE_TENANT_ID (or matching --project / --tenant arguments).
 */

const https = require('https');
const { execFileSync } = require('child_process');

function argValue(name) {
  const prefix = `--${name}=`;
  const arg = process.argv.find((value) => value.startsWith(prefix));
  return arg ? arg.slice(prefix.length) : null;
}

const PROJECT_ID = argValue('project') || process.env.FIREBASE_PROJECT_ID || '';
const TENANT_ID = argValue('tenant') || process.env.FIREBASE_TENANT_ID || '';
const ALLOWED_DEV_PROJECT_ID = process.env.ALLOWED_DEV_FIREBASE_PROJECT_ID || '';
const PRODUCTION_PROJECT_ID = 'shoeserp-clean-20260327';
const DRY_RUN = !process.argv.includes('--apply');
const DB = `projects/${PROJECT_ID}/databases/(default)/documents`;
const BASE = 'firestore.googleapis.com';

async function confirmProjectId() {
  if (!process.argv.includes('--apply')) return true;
  const target = `${PROJECT_ID}:${TENANT_ID}`;
  const prompt = `Type project:tenant to confirm reset: ${target}\n> `;
  const input = await new Promise((resolve) => {
    const rl = require('readline').createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    rl.question(prompt, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
  if (input !== target) {
    throw new Error('Target confirmation failed. Aborting reset.');
  }
  return true;
}

// ── Get access token from Firebase CLI stored credentials ──────────────────
function getToken() {
  try {
    return execFileSync('firebase', ['auth:print-access-token'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch (error) {
    const detail = String(error.stderr || error.message || '').trim();
    throw new Error(`Unable to obtain Firebase CLI token: ${detail}`);
  }
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

async function listTenantShops(token, tenantId) {
  return firestoreRequest('POST', ':runQuery', token, {
    structuredQuery: {
      from: [{ collectionId: 'customers' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'tenant_id' },
          op: 'EQUAL',
          value: { stringValue: tenantId },
        },
      },
    },
  });
}

// ── Reset logic ─────────────────────────────────────────────────────────────
async function resetInvoiceCounter(token, tenantId) {
  console.log('\n── 1. Resetting invoice counter ──');
  const res = await patchField(
    token,
    'settings',
    tenantId,
    { last_invoice_number: { integerValue: '0' } },
    ['last_invoice_number'],
  );
  if (res.error) {
    console.error('  ✗ Failed:', res.error.message);
  } else {
    console.log(`  ✓ settings/${tenantId}.last_invoice_number → 0`);
  }
}

async function resetShopBalances(token, tenantId) {
  console.log('\n── 2. Resetting shop balances ──');
  let count = 0;
  const rows = await listTenantShops(token, tenantId);
  const docs = rows.map((row) => row.document).filter(Boolean);

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

  console.log(`  Done — reset ${count} shop(s)`);
}

async function main() {
  if (!PROJECT_ID || !TENANT_ID || !ALLOWED_DEV_PROJECT_ID) {
    throw new Error(
      'Set FIREBASE_PROJECT_ID, FIREBASE_TENANT_ID, and ALLOWED_DEV_FIREBASE_PROJECT_ID before running.',
    );
  }
  if (PROJECT_ID === PRODUCTION_PROJECT_ID || PROJECT_ID !== ALLOWED_DEV_PROJECT_ID) {
    throw new Error('Refusing reset: project is not the explicitly allowlisted development project.');
  }
  if (TENANT_ID === '__global__' || TENANT_ID === 'global') {
    throw new Error('Refusing reset: a concrete tenant ID is required.');
  }
  await confirmProjectId();
  console.log('\n════════════════════════════════════════');
  console.log('  DEV RESET — financial state only');
  console.log(`  Project: ${PROJECT_ID}`);
  console.log(`  Tenant : ${TENANT_ID}`);
  console.log(`  Mode   : ${DRY_RUN ? 'DRY RUN — no writes' : 'APPLY — writes enabled'}`);
  console.log('════════════════════════════════════════');

  if (DRY_RUN) {
    console.log('\nDry run only: use --apply to actually reset balances and the invoice counter.\n');
    return;
  }

  const token = await getToken();
  console.log('  Auth: ✓ token obtained');

  await resetInvoiceCounter(token, TENANT_ID);
  await resetShopBalances(token, TENANT_ID);

  console.log('\n✓ Reset complete. All balances are 0, invoice counter is 0.\n');
}

main().catch((e) => {
  console.error('Reset failed:', e.message || e);
  process.exit(1);
});
