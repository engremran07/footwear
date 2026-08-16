const fs = require('fs');
const path = require('path');
const https = require('https');
const { execFileSync } = require('child_process');

const PROJECT = process.env.FIREBASE_PROJECT || 'shoeserp-clean-20260327';
const EMAIL = process.env.FIREBASE_TARGET_EMAIL || 'gsmenfinity@gmail.com';

function getCliToken() {
  try {
    return execFileSync('firebase', ['auth:print-access-token'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch (error) {
    const stderr = String(error.stderr || error.message || '');
    throw new Error('Unable to fetch Firebase CLI access token: ' + stderr.trim());
  }
}

function getToken() {
  if (process.env.FIREBASE_TOKEN) return process.env.FIREBASE_TOKEN;

  const HOME = process.env.USERPROFILE || process.env.HOME;
  const cfgPath = path.join(HOME, '.config', 'configstore', 'firebase-tools.json');
  if (fs.existsSync(cfgPath)) {
    try {
      const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
      if (cfg.tokens?.refresh_token) {
        const toolsApi = require('C:/Users/gsmen/AppData/Roaming/npm/node_modules/firebase-tools/lib/api.js');
        const clientId = toolsApi.clientId();
        const clientSecret = toolsApi.clientSecret();
        const refresh = cfg.tokens.refresh_token;

        return new Promise((resolve, reject) => {
          const body = new URLSearchParams({
            grant_type: 'refresh_token',
            refresh_token: refresh,
            client_id: clientId,
            client_secret: clientSecret,
          }).toString();
          const req = https.request(
            {
              hostname: 'oauth2.googleapis.com',
              path: '/token',
              method: 'POST',
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(body),
              },
            },
            (res) => {
              let data = '';
              res.on('data', (chunk) => { data += chunk; });
              res.on('end', () => {
                try {
                  const json = JSON.parse(data);
                  if (json.access_token) {
                    resolve(json.access_token);
                  } else {
                    reject(new Error('Token exchange failed: ' + data));
                  }
                } catch (e) {
                  reject(e);
                }
              });
            },
          );
          req.on('error', reject);
          req.write(body);
          req.end();
        });
      }
    } catch (_ignored) {
      // fall through to CLI token below
    }
  }

  return getCliToken();
}

function fetchJson(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ statusCode: res.statusCode, body: json });
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

(async () => {
  const token = await getToken();
  console.log('Authenticated via Firebase CLI token.');

  const query = {
    structuredQuery: {
      from: [{ collectionId: 'users' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'email' },
          op: 'EQUAL',
          value: { stringValue: EMAIL },
        },
      },
      limit: 1,
    },
  };

  const queryOptions = {
    hostname: 'firestore.googleapis.com',
    path: `/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  };

  const queryResult = await fetchJson(queryOptions, JSON.stringify(query));
  if (queryResult.statusCode !== 200) {
    throw new Error(`Query failed ${queryResult.statusCode}: ${JSON.stringify(queryResult.body)}`);
  }
  const row = queryResult.body.find((r) => r.document);
  if (!row) {
    throw new Error(`No user document found for email ${EMAIL}`);
  }
  const doc = row.document;
  const docName = doc.name;
  console.log('Found document:', docName);
  const currentTenant = doc.fields?.tenant_id?.stringValue || '__global__';

  const patchBody = {
    fields: {
      role: { stringValue: 'super_admin' },
      tenant_id: { stringValue: currentTenant },
      updated_at: { timestampValue: new Date().toISOString() },
    },
  };

  const patchOptions = {
    hostname: 'firestore.googleapis.com',
    path: `/v1/${docName}?updateMask.fieldPaths=role&updateMask.fieldPaths=tenant_id&updateMask.fieldPaths=updated_at`,
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  };

  const patchResult = await fetchJson(patchOptions, JSON.stringify(patchBody));
  if (patchResult.statusCode !== 200) {
    throw new Error(`Patch failed ${patchResult.statusCode}: ${JSON.stringify(patchResult.body)}`);
  }

  console.log('Promotion successful. New document fields:');
  console.log(JSON.stringify(patchResult.body.fields, null, 2));
})();
