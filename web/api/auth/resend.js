'use strict';

const db = require('../_lib/db.js');
const { mintToken, digest } = require('../_lib/crypto.js');
const { normaliseEmail } = require('../_lib/validate.js');
const { sendVerification } = require('../_lib/email.js');
const { baseUrl, body, clientKey, methodGuard, generic } = require('../_lib/http.js');

module.exports = async function handler(request, response) {
  if (!methodGuard(request, response, ['POST'])) return;

  const email = normaliseEmail(body(request).email);
  if (!email) return response.status(400).json({ error: 'Enter your email address.' });

  try {
    const allowed = await db.throttle('resend:' + clientKey(request), 5, 60 * 60);
    if (!allowed) {
      return response.status(429).json({ error: 'Too many requests. Try again in an hour.' });
    }

    const user = await db.findUserByEmail(email);
    // Same answer either way, whether the account is missing or already done.
    if (user && !user.verified_at) {
      const token = mintToken();
      await db.createVerification(user.id, digest(token), new Date(Date.now() + 24 * 60 * 60 * 1000));
      await sendVerification(email, baseUrl(request) + '/api/auth/verify?token=' + encodeURIComponent(token));
    }
    return generic(response);
  } catch (error) {
    console.error('[resend]', error && error.message);
    return response.status(500).json({ error: 'Could not send the email. Try again shortly.' });
  }
};
