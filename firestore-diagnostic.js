#!/usr/bin/env node
'use strict';

const admin = require('firebase-admin');

const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
const workspaceId = process.env.WORKSPACE_ID?.trim();

if (!projectId || !workspaceId || workspaceId === '__global__') {
  console.error(
    'Set FIREBASE_PROJECT_ID and a concrete WORKSPACE_ID. ' +
      'Global or unscoped diagnostics are not supported.',
  );
  process.exitCode = 1;
} else {
  const app = admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
  const db = admin.firestore();
  const sampleLimit = 1000;

  async function countWorkspaceDocuments(collection) {
    const snapshot = await db
      .collection(collection)
      .where('tenant_id', '==', workspaceId)
      .limit(sampleLimit + 1)
      .get();

    return {
      count: Math.min(snapshot.size, sampleLimit),
      truncated: snapshot.size > sampleLimit,
    };
  }

  async function diagnoseWorkspace() {
    try {
      const tenant = await db.collection('tenants').doc(workspaceId).get();
      if (!tenant.exists) {
        throw new Error('Workspace document does not exist.');
      }

      const tenantData = tenant.data();
      console.log(`Project: ${projectId}`);
      console.log(`Workspace: ${workspaceId}`);
      console.log(`Workspace active: ${tenantData.active === true}`);

      for (const collection of [
        'users',
        'customers',
        'transactions',
        'invoices',
      ]) {
        const result = await countWorkspaceDocuments(collection);
        console.log(
          `${collection}: at least ${result.count}` +
            (result.truncated ? ` (truncated at ${sampleLimit})` : ''),
        );
      }

      console.log(
        'Counts are tenant-scoped samples; review firestore.indexes.json ' +
          'separately for query-index coverage.',
      );
    } finally {
      await app.delete();
    }
  }

  diagnoseWorkspace().catch((error) => {
    console.error(
      `Workspace diagnostic failed (${error.code || error.name || 'unknown'}).`,
    );
    process.exitCode = 1;
  });
}
