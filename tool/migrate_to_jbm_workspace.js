'use strict';

console.error(
  'Disabled: this legacy tenant migration bypasses current tenant, ' +
    'ledger, and inventory integrity safeguards. No data was changed.',
);
process.exitCode = 1;
