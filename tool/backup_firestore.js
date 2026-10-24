'use strict';

console.error(
  'Disabled: plaintext project-wide exports are unsupported. Use the encrypted, workspace-scoped backup in the app.',
);
process.exitCode = 1;
