// Small helpers shared by the auth endpoints.
'use strict';

function baseUrl(request) {
  if (process.env.PUBLIC_BASE_URL) return process.env.PUBLIC_BASE_URL.replace(/\/$/, '');
  const proto = request.headers['x-forwarded-proto'] || 'https';
  const host = request.headers['x-forwarded-host'] || request.headers.host;
  return proto + '://' + host;
}

function body(request) {
  if (request.body && typeof request.body === 'object') return request.body;
  if (typeof request.body === 'string') {
    try { return JSON.parse(request.body); } catch (_) { return {}; }
  }
  return {};
}

function clientKey(request) {
  const forwarded = request.headers['x-forwarded-for'] || '';
  return String(forwarded).split(',')[0].trim() || 'unknown';
}

function methodGuard(request, response, allowed) {
  if (allowed.includes(request.method)) return true;
  response.setHeader('Allow', allowed.join(', '));
  response.status(405).json({ error: 'Method not allowed.' });
  return false;
}

// Every failure path answers the same way, so a caller cannot learn which
// accounts exist by watching for a different shape or a different delay.
function generic(response) {
  return response.status(200).json({
    ok: true,
    message: 'If that address can be used, a verification email is on its way. Check your inbox and spam folder.'
  });
}

module.exports = { baseUrl, body, clientKey, methodGuard, generic };
