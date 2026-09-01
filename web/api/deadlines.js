'use strict';

const db = require('./_lib/db.js');
const { requireUser } = require('./_lib/session.js');
const { body, methodGuard } = require('./_lib/http.js');

// Server-side storage for someone with an account. This is what makes the data
// genuinely private: the rows are keyed by a verified session, so another
// person at the same computer cannot read them out of the browser.
const MAX_ITEMS = 2000;

module.exports = async function handler(request, response) {
  if (!methodGuard(request, response, ['GET', 'PUT'])) return;

  const user = await requireUser(request, response);
  if (!user) return undefined;

  response.setHeader('Cache-Control', 'no-store');

  try {
    if (request.method === 'GET') {
      const data = await db.loadUserData(user.id);
      return response.status(200).json({
        deadlines: data.deadlines || [],
        settings: data.settings || {}
      });
    }

    const input = body(request);
    const deadlines = Array.isArray(input.deadlines) ? input.deadlines : [];
    const settings = input.settings && typeof input.settings === 'object' ? input.settings : {};

    if (deadlines.length > MAX_ITEMS) {
      return response.status(413).json({ error: 'Too many items to store.' });
    }

    await db.saveUserData(user.id, deadlines, settings);
    return response.status(200).json({ ok: true, count: deadlines.length });
  } catch (error) {
    console.error('[deadlines]', error && error.message);
    return response.status(500).json({ error: 'Could not reach your saved deadlines.' });
  }
};
