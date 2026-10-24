'use strict';

console.error(
  'Disabled: direct balance resets bypass the ledger and can corrupt financial state. Preserve shop.balance with its transactions and invoices.',
);
process.exitCode = 1;
