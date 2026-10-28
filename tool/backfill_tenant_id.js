'use strict';

console.error(
  'Disabled: assigning every unscoped record to one tenant is unsafe for a ' +
    'multi-workspace migration. Use a reviewed, record-mapped migration. No data was changed.',
);
process.exitCode = 1;
