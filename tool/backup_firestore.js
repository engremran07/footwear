/**
 * backup_firestore.js — Production-safe Firestore backup
 *
 * Reads all 11 canonical collections via the REST API and writes a single
 * pretty-printed JSON file to  backups/backup_YYYY-MM-DD_HH-MM-SS.json.
 *
 * Uses the Firebase CLI refresh token (same auth pattern as dev_reset.js).
 * Run from repo root:  node tool/backup_firestore.js
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

const PROJECT = 'shoeserp-clean-20260327';
const DB = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = 'firestore.googleapis.com';

const COLLECTIONS = [
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
  'admin_config',
];

// ── Auth — reuse Firebase CLI refresh token ─────────────────────────────────
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
function firestoreGet(urlPath, token) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: BASE,
      path: `/v1/${DB}${urlPath}`,
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` },
    };
    let data = '';
    const req = https.request(options, (res) => {
      res.on('data', (d) => (data += d));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch { resolve(data); }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

// ── Firestore value decoder ─────────────────────────────────────────────────
function decodeValue(val) {
  if (val === undefined || val === null) return null;
  if ('stringValue' in val) return val.stringValue;
  if ('integerValue' in val) return Number(val.integerValue);
  if ('doubleValue' in val) return val.doubleValue;
  if ('booleanValue' in val) return val.booleanValue;
  if ('timestampValue' in val) return val.timestampValue;
  if ('nullValue' in val) return null;
  if ('arrayValue' in val) {
    return (val.arrayValue.values || []).map(decodeValue);
  }
  if ('mapValue' in val) {
    return decodeFields(val.mapValue.fields || {});
  }
  // geoPointValue, referenceValue, bytesValue — store raw
  return val;
}

function decodeFields(fields) {
  if (!fields) return {};
  const obj = {};
  for (const [key, val] of Object.entries(fields)) {
    obj[key] = decodeValue(val);
  }
  return obj;
}

// ── Read all docs from a collection (paginated) ─────────────────────────────
async function readCollection(token, collectionId) {
  const docs = [];
  let pageToken = null;

  do {
    const qs = pageToken
      ? `?pageSize=300&pageToken=${pageToken}`
      : '?pageSize=300';
    const page = await firestoreGet(`/${collectionId}${qs}`, token);

    if (page.error) {
      console.error(`  ✗ ${collectionId}: ${page.error.message}`);
      break;
    }

    const pageDocs = page.documents || [];
    for (const doc of pageDocs) {
      const docId = doc.name.split('/').pop();
      docs.push({ _id: docId, ...decodeFields(doc.fields) });
    }

    pageToken = page.nextPageToken || null;
  } while (pageToken);

  return docs;
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  const now = new Date();
  const stamp = now.toISOString().replace(/[T:]/g, '-').replace(/\..+/, '');
  const outFile = path.join(__dirname, '..', 'backups', `backup_${stamp}.json`);

  console.log('\n══════════════════════════════════════════');
  console.log('  FIRESTORE BACKUP');
  console.log(`  Project: ${PROJECT}`);
  console.log(`  Output:  ${outFile}`);
  console.log('══════════════════════════════════════════\n');

  const token = await getToken();
  console.log('  Auth: ✓ token obtained\n');

  const backup = {
    _meta: {
      project: PROJECT,
      timestamp: now.toISOString(),
      collections: COLLECTIONS,
    },
  };

  let totalDocs = 0;

  for (const col of COLLECTIONS) {
    process.stdout.write(`  ${col} ... `);
    const docs = await readCollection(token, col);
    backup[col] = docs;
    totalDocs += docs.length;
    console.log(`${docs.length} docs`);
  }

  // Ensure output directory exists
  const outDir = path.dirname(outFile);
  if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
  }

  fs.writeFileSync(outFile, JSON.stringify(backup, null, 2), 'utf8');

  const sizeMb = (fs.statSync(outFile).size / (1024 * 1024)).toFixed(2);

  console.log(`\n✓ Backup complete — ${totalDocs} documents, ${sizeMb} MB`);
  console.log(`  File: ${outFile}\n`);
}

main().catch((e) => {
  console.error('Backup failed:', e.message || e);
  process.exit(1);
});
