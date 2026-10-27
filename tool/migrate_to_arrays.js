'use strict';

console.error(
  'Disabled: this legacy global assignment migration can update users and ' +
    'routes outside a tenant-scoped, reviewed migration. No data was changed.',
);
process.exitCode = 1;
