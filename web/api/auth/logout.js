'use strict';

const { endSession } = require('../_lib/session.js');
const { methodGuard } = require('../_lib/http.js');

module.exports = async function handler(request, response) {
  if (!methodGuard(request, response, ['POST'])) return;
  try {
    await endSession(request, response);
  } catch (error) {
    console.error('[logout]', error && error.message);
  }
  return response.status(200).json({ ok: true });
};
