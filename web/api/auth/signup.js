'use strict';

const db = require('../_lib/db.js');
const { hashPassword, mintToken, digest } = require('../_lib/crypto.js');
const { checkEmail, checkPassword, normaliseEmail } = require('../_lib/validate.js');
const { sendVerification } = require('../_lib/email.js');
const { baseUrl, body, clientKey, methodGuard, generic } = require('../_lib/http.js');

const VERIFICATION_HOURS = 24;

module.exports = async function handler(request, response) {
  if (!methodGuard(request, response, ['POST'])) return;

  const input = body(request);
  const email = normaliseEmail(input.email);
  const password = String(input.password || '');

  // Validation errors are safe to report precisely: they are about what was
  // typed, not about who already has an account.
  const emailProblem = checkEmail(email);
  if (emailProblem) return response.status(400).json({ error: emailProblem });
  const passwordProblem = checkPassword(password, email);
  if (passwordProblem) return response.status(400).json({ error: passwordProblem });

  try {
    const allowed = await db.throttle('signup:' + clientKey(request), 5, 60 * 60);
    if (!allowed) {
      return response.status(429).json({ error: 'Too many sign-up attempts. Try again in an hour.' });
    }

    const existing = await db.findUserByEmail(email);

    // Already verified: say nothing that distinguishes this from a new address,
    // or the endpoint becomes a way to test which emails have accounts.
    if (existing && existing.verified_at) return generic(response);

    const user = existing || await db.createUser(email, await hashPassword(password));

    // An unverified account can be re-claimed with a new password: nobody has
    // proved they own the address yet, so there is nothing to protect.
    if (existing) await db.updatePassword(user.id, await hashPassword(password));

    const token = mintToken();
    await db.createVerification(
      user.id,
      digest(token),
      new Date(Date.now() + VERIFICATION_HOURS * 60 * 60 * 1000)
    );

    await sendVerification(email, baseUrl(request) + '/api/auth/verify?token=' + encodeURIComponent(token));
    return generic(response);
  } catch (error) {
    console.error('[signup]', error && error.message);
    return response.status(500).json({ error: 'Could not create the account. Try again shortly.' });
  }
};
