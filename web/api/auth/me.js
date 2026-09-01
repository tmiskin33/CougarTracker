'use strict';

const { currentUser } = require('../_lib/session.js');
const { methodGuard } = require('../_lib/http.js');

// The app asks this on load to find out whether it already has a session.
module.exports = async function handler(request, response) {
  if (!methodGuard(request, response, ['GET'])) return;
  response.setHeader('Cache-Control', 'no-store');
  try {
    const user = await currentUser(request);
    return response.status(200).json({ user: user ? { email: user.email } : null });
  } catch (error) {
    console.error('[me]', error && error.message);
    return response.status(200).json({ user: null });
  }
};
