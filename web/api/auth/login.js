'use strict';

const db = require('../_lib/db.js');
const { hashPassword, verifyPassword } = require('../_lib/crypto.js');
const { normaliseEmail } = require('../_lib/validate.js');
const { body, clientKey, methodGuard } = require('../_lib/http.js');
const { startSession } = require('../_lib/session.js');

// Compared against when no such account exists, so a missing account costs the
// same time as a wrong password and cannot be told apart by a stopwatch.
let decoyHash = null;
async function decoy() {
  if (!decoyHash) decoyHash = await hashPassword('decoy-for-constant-time-comparison');
  return decoyHash;
}

module.exports = async function handler(request, response) {
  if (!methodGuard(request, response, ['POST'])) return;

  const input = body(request);
  const email = normaliseEmail(input.email);
  const password = String(input.password || '');

  if (!email || !password) {
    return response.status(400).json({ error: 'Enter your email and password.' });
  }

  try {
    const allowed = await db.throttle('login:' + email + ':' + clientKey(request), 10, 15 * 60);
    if (!allowed) {
      return response.status(429).json({ error: 'Too many attempts. Wait 15 minutes and try again.' });
    }

    const user = await db.findUserByEmail(email);
    const matches = await verifyPassword(password, user ? user.password_hash : await decoy());

    // One message for both "no such account" and "wrong password", so this
    // endpoint cannot be used to enumerate who has signed up.
    if (!user || !matches) {
      return response.status(401).json({ error: 'That email and password do not match an account.' });
    }

    if (!user.verified_at) {
      return response.status(403).json({
        error: 'Confirm your email address first. Check your inbox for the link.',
        needsVerification: true
      });
    }

    await startSession(response, user.id);
    return response.status(200).json({ email: user.email });
  } catch (error) {
    console.error('[login]', error && error.message);
    return response.status(500).json({ error: 'Could not sign in. Try again shortly.' });
  }
};
