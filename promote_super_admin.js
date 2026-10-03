const https = require('https');
const { execFileSync } = require('child_process');

const PROJECT = process.env.FIREBASE_PROJECT_ID || '';
const EMAIL = process.env.FIREBASE_TARGET_EMAIL || '';

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
  if (!PROJECT || !EMAIL) {
    throw new Error('Set FIREBASE_PROJECT_ID and FIREBASE_TARGET_EMAIL explicitly.');
  }
  const token = getCliToken();
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
  const patchBody = {
    fields: {
      role: { stringValue: 'super_admin' },
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
