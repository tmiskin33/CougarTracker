// Password hashing, token minting, and constant-time comparison.
//
// Node's crypto module covers all of it, so there is no dependency here and
// nothing hand-rolled: scrypt for passwords, randomBytes for tokens, SHA-256
// for storing token digests, timingSafeEqual for every comparison.
'use strict';

const crypto = require('node:crypto');

// Deliberately slow. These parameters cost roughly 100ms per hash, which is
// nothing for one login and ruinous for someone working through a stolen
// database.
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 32 };

function hashPassword(password) {
  return new Promise(function (resolve, reject) {
    const salt = crypto.randomBytes(16);
    crypto.scrypt(password, salt, SCRYPT.keylen, SCRYPT, function (error, derived) {
      if (error) { reject(error); return; }
      resolve([
        'scrypt', SCRYPT.N, SCRYPT.r, SCRYPT.p,
        salt.toString('base64'), derived.toString('base64')
      ].join('$'));
    });
  });
}

function verifyPassword(password, stored) {
  return new Promise(function (resolve) {
    if (typeof stored !== 'string') { resolve(false); return; }
    const parts = stored.split('$');
    if (parts.length !== 6 || parts[0] !== 'scrypt') { resolve(false); return; }

    const options = { N: Number(parts[1]), r: Number(parts[2]), p: Number(parts[3]), keylen: SCRYPT.keylen };
    if (!options.N || !options.r || !options.p) { resolve(false); return; }

    let salt;
    let expected;
    try {
      salt = Buffer.from(parts[4], 'base64');
      expected = Buffer.from(parts[5], 'base64');
    } catch (_) { resolve(false); return; }

    crypto.scrypt(password, salt, options.keylen, options, function (error, derived) {
      if (error || derived.length !== expected.length) { resolve(false); return; }
      resolve(crypto.timingSafeEqual(derived, expected));
    });
  });
}

// Session and verification tokens. The raw token goes to the user; only its
// digest is stored, so a database leak does not hand over live sessions.
function mintToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function digest(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

function safeEqualHex(a, b) {
  const left = Buffer.from(String(a), 'utf8');
  const right = Buffer.from(String(b), 'utf8');
  if (left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

module.exports = { hashPassword, verifyPassword, mintToken, digest, safeEqualHex, SCRYPT };
