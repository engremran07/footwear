'use strict';

console.error(
  'Disabled: assigning unscoped records to a default tenant can expose data across workspaces. ' +
    'Use a reviewed, tenant-specific migration. No data was changed.',
);
process.exitCode = 1;
