// Session cookies and the guard every authenticated endpoint runs.
'use strict';

const { mintToken, digest } = require('./crypto.js');
const db = require('./db.js');

const COOKIE = 'cdt_session';
const LIFETIME_DAYS = 30;

function parseCookies(request) {
  const header = request.headers.cookie || '';
  const out = {};
  for (const part of header.split(';')) {
    const index = part.indexOf('=');
    if (index === -1) continue;
    out[part.slice(0, index).trim()] = decodeURIComponent(part.slice(index + 1).trim());
  }
  return out;
}

// HttpOnly so script cannot read it — the whole point, since script is exactly
// what could read localStorage. Secure so it never crosses plain http. SameSite
// Lax so another site cannot ride the session with a cross-site request.
function setSessionCookie(response, token, maxAgeSeconds) {
  const parts = [
    COOKIE + '=' + encodeURIComponent(token),
    'Path=/',
    'HttpOnly',
    'SameSite=Lax',
    'Max-Age=' + maxAgeSeconds
  ];
  if (process.env.NODE_ENV !== 'development') parts.push('Secure');
  response.setHeader('Set-Cookie', parts.join('; '));
}

function clearSessionCookie(response) {
  setSessionCookie(response, '', 0);
}

async function startSession(response, userId) {
  const token = mintToken();
  const expires = new Date(Date.now() + LIFETIME_DAYS * 24 * 60 * 60 * 1000);
  await db.createSession(userId, digest(token), expires);
  setSessionCookie(response, token, LIFETIME_DAYS * 24 * 60 * 60);
  return token;
}

async function endSession(request, response) {
  const token = parseCookies(request)[COOKIE];
  if (token) await db.deleteSession(digest(token));
  clearSessionCookie(response);
}

// Returns the signed-in user, or null. Endpoints that need an account call
// `requireUser` instead, which answers 401 for them.
async function currentUser(request) {
  const token = parseCookies(request)[COOKIE];
  if (!token) return null;
  const session = await db.findSession(digest(token));
  if (!session || !session.verified_at) return null;
  return { id: session.user_id, email: session.email, verifiedAt: session.verified_at };
}

async function requireUser(request, response) {
  const user = await currentUser(request);
  if (!user) {
    response.status(401).json({ error: 'Sign in to continue.' });
    return null;
  }
  return user;
}

module.exports = {
  COOKIE, LIFETIME_DAYS, parseCookies, setSessionCookie, clearSessionCookie,
  startSession, endSession, currentUser, requireUser
};
