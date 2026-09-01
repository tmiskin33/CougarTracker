'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { hashPassword, verifyPassword, mintToken, digest, safeEqualHex } = require('../api/_lib/crypto.js');
const { checkEmail, checkPassword, normaliseEmail } = require('../api/_lib/validate.js');

test('a password verifies against its own hash and nothing else', async () => {
  const stored = await hashPassword('correct horse battery');
  assert.equal(await verifyPassword('correct horse battery', stored), true);
  assert.equal(await verifyPassword('correct horse batteru', stored), false);
  assert.equal(await verifyPassword('', stored), false);
});

test('the same password hashes differently every time', async () => {
  // Distinct salts, so two people with the same password do not share a hash
  // and a precomputed table is worthless.
  const a = await hashPassword('correct horse battery');
  const b = await hashPassword('correct horse battery');
  assert.notEqual(a, b);
  assert.equal(await verifyPassword('correct horse battery', b), true);
});

test('the stored hash contains no trace of the password', async () => {
  const stored = await hashPassword('sunflower-tuesday-42');
  assert.ok(!stored.includes('sunflower'));
  assert.ok(stored.startsWith('scrypt$16384$8$1$'));
});

test('a malformed stored hash is rejected rather than throwing', async () => {
  for (const bad of ['', 'nonsense', 'scrypt$only$three$parts', null, undefined, 'md5$1$1$1$a$b']) {
    assert.equal(await verifyPassword('anything', bad), false);
  }
});

test('tokens are unguessable and stored only as digests', () => {
  const token = mintToken();
  assert.ok(token.length >= 40);
  assert.notEqual(mintToken(), mintToken());

  const stored = digest(token);
  assert.equal(stored.length, 64);
  assert.ok(!stored.includes(token));
  assert.equal(digest(token), stored, 'the same token always digests the same');
});

test('digest comparison is length-safe', () => {
  const a = digest('one');
  assert.equal(safeEqualHex(a, a), true);
  assert.equal(safeEqualHex(a, digest('two')), false);
  assert.equal(safeEqualHex(a, 'short'), false, 'differing lengths must not throw');
});

test('emails are normalised before use', () => {
  assert.equal(normaliseEmail('  Tanner@BYU.edu '), 'tanner@byu.edu');
});

test('obvious non-addresses are refused', () => {
  assert.equal(checkEmail('student@byu.edu'), null);
  assert.ok(checkEmail(''));
  assert.ok(checkEmail('no-at-sign'));
  assert.ok(checkEmail('trailing@dot'));
  assert.ok(checkEmail('a@b@c.com'));
});

test('passwords are judged on length, not on symbol theatre', () => {
  assert.equal(checkPassword('a long enough passphrase'), null);
  assert.ok(checkPassword('Sh0rt!'), 'nine characters or fewer is refused however punctuated');
  assert.equal(checkPassword('aaaaaaaaaaaa'), null, 'no arbitrary character-class rule');
});

test('breached and self-referential passwords are refused', () => {
  assert.ok(checkPassword('password123'));
  assert.ok(checkPassword('tanner-is-my-password', 'tanner@byu.edu'), 'contains the email local part');
});

test('a very short local part does not poison the containment check', () => {
  // For a@b.co the local part is one letter, which appears in nearly every
  // password. The rule has to be meaningful or it rejects good passwords.
  assert.equal(checkPassword('a long enough passphrase', 'a@b.co'), null);
  assert.equal(checkPassword('the quick brown fox', 'ab@byu.edu'), null);
});
