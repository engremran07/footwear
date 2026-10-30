const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const webDirectory = path.join(__dirname, '..', 'app', 'web');

test('privacy policy is a complete, publication-ready static page', () => {
  const html = fs.readFileSync(
    path.join(webDirectory, 'privacy-policy.html'),
    'utf8',
  );

  for (const requiredText of [
    'Privacy Policy',
    'Aeonis Labs',
    'a3onislabs@gmail.com',
    'Multan, Pakistan',
    '30 days',
    '365 days',
    'account-deletion.html',
  ]) {
    assert.ok(html.includes(requiredText), `Missing policy text: ${requiredText}`);
  }

  assert.doesNotMatch(html, /\[OWNER:|Draft — not approved/);
});

test('account deletion page explains the manual request and retention scope', () => {
  const html = fs.readFileSync(
    path.join(webDirectory, 'account-deletion.html'),
    'utf8',
  );

  for (const requiredText of [
    'Request account deletion',
    'mailto:a3onislabs@gmail.com',
    '30 days',
    '365 days',
    'financial',
    'not automatically deleted',
    'privacy-policy.html',
  ]) {
    assert.ok(html.includes(requiredText), `Missing deletion text: ${requiredText}`);
  }

  assert.doesNotMatch(html, /\[OWNER:|Draft — not approved/);
});
