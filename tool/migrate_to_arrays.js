/**
 * migrate_to_arrays.js — ONE-TIME MIGRATION
 *
 * Normalizes all Firestore docs from legacy scalar assignment fields
 * to array-only fields, then removes the scalar fields.
 *
 * For USERS collection:
 *   - If assigned_route_ids is empty/missing but assigned_route_id exists:
 *     copy scalar → array
 *   - Delete: assigned_route_id, assigned_route_name
 *
 * For ROUTES collection:
 *   - If assigned_seller_ids is empty/missing but assigned_seller_id exists:
 *     copy scalar → array
 *   - Delete: assigned_seller_id, assigned_seller_name
 *
 * Uses Firebase CLI refresh token (no service account needed).
 * Run from repo root: node tool/migrate_to_arrays.js
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

// List all docs in a collection
async function listAll(token, collection) {
  const docs = [];
  let pageToken = '';
  while (true) {
    const qs = pageToken ? `?pageToken=${pageToken}&pageSize=300` : '?pageSize=300';
    const res = await firestoreRequest('GET', `/${collection}${qs}`, token);
    if (res.documents) docs.push(...res.documents);
    if (res.nextPageToken) pageToken = res.nextPageToken;
    else break;
  }
  return docs;
}

// Extract string value from Firestore REST field
function strVal(field) {
  if (!field) return null;
  if (field.stringValue !== undefined && field.stringValue !== '') return field.stringValue;
  return null;
}

// Extract array of strings from Firestore REST field
function arrVal(field) {
  if (!field || !field.arrayValue || !field.arrayValue.values) return [];
  return field.arrayValue.values
    .map((v) => v.stringValue)
    .filter((v) => v !== undefined && v !== '');
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  console.log('🔑 Getting access token...');
  const token = await getToken();

  // ── Migrate USERS ──────────────────────────────────────────────────────
  console.log('\n📋 Migrating USERS collection...');
  const users = await listAll(token, 'users');
  console.log(`   Found ${users.length} user docs`);

  let usersMigrated = 0;
  for (const doc of users) {
    const docId = doc.name.split('/').pop();
    const fields = doc.fields || {};

    const scalarRouteId = strVal(fields.assigned_route_id);
    const scalarRouteName = strVal(fields.assigned_route_name);
    const arrayRouteIds = arrVal(fields.assigned_route_ids);
    const arrayRouteNames = arrVal(fields.assigned_route_names);

    // Build the update: copy scalar → array if array is empty
    const update = {};
    const masks = [];

    if (arrayRouteIds.length === 0 && scalarRouteId) {
      update.assigned_route_ids = {
        arrayValue: { values: [{ stringValue: scalarRouteId }] },
      };
      masks.push('assigned_route_ids');
    }
    if (arrayRouteNames.length === 0 && scalarRouteName) {
      update.assigned_route_names = {
        arrayValue: { values: [{ stringValue: scalarRouteName }] },
      };
      masks.push('assigned_route_names');
    }

    // Always delete scalar fields by setting them to null
    if (fields.assigned_route_id !== undefined) {
      update.assigned_route_id = { nullValue: null };
      masks.push('assigned_route_id');
    }
    if (fields.assigned_route_name !== undefined) {
      update.assigned_route_name = { nullValue: null };
      masks.push('assigned_route_name');
    }

    if (masks.length > 0) {
      const mask = masks.map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join('&');
      await firestoreRequest('PATCH', `/users/${docId}?${mask}`, token, { fields: update });
      usersMigrated++;
      console.log(`   ✅ ${docId} — migrated (${masks.join(', ')})`);
    } else {
      console.log(`   ⏭️  ${docId} — already clean`);
    }
  }

  // ── Migrate ROUTES ─────────────────────────────────────────────────────
  console.log('\n📋 Migrating ROUTES collection...');
  const routes = await listAll(token, 'routes');
  console.log(`   Found ${routes.length} route docs`);

  let routesMigrated = 0;
  for (const doc of routes) {
    const docId = doc.name.split('/').pop();
    const fields = doc.fields || {};

    const scalarSellerId = strVal(fields.assigned_seller_id);
    const scalarSellerName = strVal(fields.assigned_seller_name);
    const arraySellerIds = arrVal(fields.assigned_seller_ids);
    const arraySellerNames = arrVal(fields.assigned_seller_names);

    const update = {};
    const masks = [];

    if (arraySellerIds.length === 0 && scalarSellerId) {
      update.assigned_seller_ids = {
        arrayValue: { values: [{ stringValue: scalarSellerId }] },
      };
      masks.push('assigned_seller_ids');
    }
    if (arraySellerNames.length === 0 && scalarSellerName) {
      update.assigned_seller_names = {
        arrayValue: { values: [{ stringValue: scalarSellerName }] },
      };
      masks.push('assigned_seller_names');
    }

    // Always delete scalar fields
    if (fields.assigned_seller_id !== undefined) {
      update.assigned_seller_id = { nullValue: null };
      masks.push('assigned_seller_id');
    }
    if (fields.assigned_seller_name !== undefined) {
      update.assigned_seller_name = { nullValue: null };
      masks.push('assigned_seller_name');
    }

    if (masks.length > 0) {
      const mask = masks.map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`).join('&');
      await firestoreRequest('PATCH', `/routes/${docId}?${mask}`, token, { fields: update });
      routesMigrated++;
      console.log(`   ✅ ${docId} — migrated (${masks.join(', ')})`);
    } else {
      console.log(`   ⏭️  ${docId} — already clean`);
    }
  }

  console.log(`\n🎉 Migration complete!`);
  console.log(`   Users migrated: ${usersMigrated}/${users.length}`);
  console.log(`   Routes migrated: ${routesMigrated}/${routes.length}`);
  console.log('\n⚠️  Next steps:');
  console.log('   1. Deploy updated Firestore rules (array-based)');
  console.log('   2. Deploy updated code (no dual-write)');
  console.log('   3. Verify admin + seller login works');
}

main().catch((err) => {
  console.error('❌ Migration failed:', err);
  process.exit(1);
});
