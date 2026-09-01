'use strict';

const db = require('../_lib/db.js');
const { digest } = require('../_lib/crypto.js');
const { baseUrl, methodGuard } = require('../_lib/http.js');

// The link from the email. It marks the address confirmed and sends the user
// back to the app to sign in — deliberately without starting a session, since
// anything that follows links in email (scanners, previewers) would otherwise
// be handed one.
module.exports = async function handler(request, response) {
  if (!methodGuard(request, response, ['GET'])) return;

  const token = request.query && request.query.token;
  const home = baseUrl(request) + '/';

  if (!token || Array.isArray(token)) {
    response.writeHead(302, { Location: home + '?verified=invalid' });
    return response.end();
  }

  try {
    const userId = await db.consumeVerification(digest(token));
    response.writeHead(302, { Location: home + (userId ? '?verified=1' : '?verified=expired') });
    return response.end();
  } catch (error) {
    console.error('[verify]', error && error.message);
    response.writeHead(302, { Location: home + '?verified=error' });
    return response.end();
  }
};
