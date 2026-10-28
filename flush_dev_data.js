'use strict';

console.error(
  'Disabled: bulk deletion and balance reset can break financial and inventory links. ' +
    'No data was changed.',
);
process.exitCode = 1;
