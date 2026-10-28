'use strict';

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { test } = require('node:test');

const repositoryRoot = path.resolve(__dirname, '..');
const disabledScripts = [
  'dev_reset.js',
  'dev_restore.js',
  'flush_dev_data.js',
  'migrate_jbm_workspace.js',
  'migrate_to_jbm_workspace.js',
  'tool/backup_firestore.js',
  'tool/backfill_tenant_id.js',
  'tool/backfill_missing_tenant_id.js',
  'tool/migrate_to_arrays.js',
  'tool/migrate_to_jbm_workspace.js',
];

for (const script of disabledScripts) {
  test(`${script} fails closed with an explicit disabled message`, () => {
    const result = spawnSync(process.execPath, [path.join(repositoryRoot, script)], {
      cwd: repositoryRoot,
      encoding: 'utf8',
    });

    assert.equal(result.error, undefined);
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /^Disabled:/m);
  });
}
