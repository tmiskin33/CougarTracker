'use strict';
const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');

// Patch the data and email layers before the endpoints capture them, so these
// exercise the real handler logic against an in-memory store.
const db = require('../api/_lib/db.js');
const email = require('../api/_lib/email.js');
const { hashPassword } = require('../api/_lib/crypto.js');

const state = { users: [], verifications: [], sessions: [], data: new Map(), sent: [], throttled: false };

function resetState() {
  state.users = [];
  state.verifications = [];
  state.sessions = [];
  state.data = new Map();
  state.sent = [];
  state.throttled = false;
}

Object.assign(db, {
  async ensureSchema() {},
  async findUserByEmail(e) { return state.users.find((u) => u.email === e) || null; },
  async findUserById(id) { return state.users.find((u) => u.id === id) || null; },
  async createUser(e, hash) {
    const user = { id: crypto.randomUUID(), email: e, password_hash: hash, verified_at: null };
    state.users.push(user);
    return user;
  },
  async updatePassword(id, hash) {
    const user = state.users.find((u) => u.id === id);
    if (user) user.password_hash = hash;
  },
  async createVerification(userId, tokenHash, expiresAt) {
    state.verifications = state.verifications.filter((v) => v.userId !== userId);
    state.verifications.push({ userId, tokenHash, expiresAt });
  },
  async consumeVerification(tokenHash) {
    const index = state.verifications.findIndex((v) => v.tokenHash === tokenHash && v.expiresAt > new Date());
    if (index === -1) return null;
    const [entry] = state.verifications.splice(index, 1);
    const user = state.users.find((u) => u.id === entry.userId);
    if (user) user.verified_at = new Date();
    return entry.userId;
  },
  async createSession(userId, tokenHash, expiresAt) { state.sessions.push({ userId, tokenHash, expiresAt }); },
  async findSession(tokenHash) {
    const session = state.sessions.find((s) => s.tokenHash === tokenHash && s.expiresAt > new Date());
    if (!session) return null;
    const user = state.users.find((u) => u.id === session.userId);
    return { user_id: user.id, email: user.email, verified_at: user.verified_at };
  },
  async deleteSession(tokenHash) { state.sessions = state.sessions.filter((s) => s.tokenHash !== tokenHash); },
  async deleteAllSessions(userId) { state.sessions = state.sessions.filter((s) => s.userId !== userId); },
  async loadUserData(userId) { return state.data.get(userId) || { deadlines: [], settings: {} }; },
  async saveUserData(userId, deadlines, settings) { state.data.set(userId, { deadlines, settings }); },
  async throttle() { return !state.throttled; }
});

email.sendVerification = async function (to, link) {
  state.sent.push({ to, link });
  return { sent: true };
};

const signup = require('../api/auth/signup.js');
const verify = require('../api/auth/verify.js');
const login = require('../api/auth/login.js');
const logout = require('../api/auth/logout.js');
const me = require('../api/auth/me.js');
const deadlines = require('../api/deadlines.js');

function makeResponse() {
  const captured = { status: 200, body: null, headers: {}, redirect: null };
  const response = {
    captured,
    setHeader(key, value) { captured.headers[key.toLowerCase()] = value; },
    status(code) { captured.status = code; return response; },
    json(payload) { captured.body = payload; return captured; },
    send(payload) { captured.body = payload; return captured; },
    writeHead(code, headers) { captured.status = code; captured.redirect = headers.Location; return response; },
    end() { return captured; }
  };
  return response;
}

async function call(handler, request) {
  const response = makeResponse();
  await handler(Object.assign({ headers: { host: 'app.test' }, query: {}, body: {} }, request), response);
  return response.captured;
}

function tokenFrom(link) {
  return decodeURIComponent(link.split('token=')[1]);
}

function cookieFrom(result) {
  const header = result.headers['set-cookie'] || '';
  return String(header).split(';')[0];
}

// ---------- sign up ----------

test('sign-up refuses a bad address and a weak password', async () => {
  resetState();
  assert.equal((await call(signup, { method: 'POST', body: { email: 'nope', password: 'a long password' } })).status, 400);
  assert.equal((await call(signup, { method: 'POST', body: { email: 'a@b.co', password: 'short' } })).status, 400);
  assert.equal(state.users.length, 0);
});

test('sign-up creates an unverified account and emails a link', async () => {
  resetState();
  const result = await call(signup, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });

  assert.equal(result.status, 200);
  assert.equal(state.users.length, 1);
  assert.equal(state.users[0].verified_at, null, 'not verified until the link is used');
  assert.equal(state.sent.length, 1);
  assert.match(state.sent[0].link, /\/api\/auth\/verify\?token=/);
});

test('the password is never stored as typed', async () => {
  resetState();
  await call(signup, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });
  const stored = state.users[0].password_hash;
  assert.ok(!stored.includes('passphrase'));
  assert.ok(stored.startsWith('scrypt$'));
});

test('signing up with an address that already has a verified account gives nothing away', async () => {
  resetState();
  await call(signup, { method: 'POST', body: { email: 'taken@byu.edu', password: 'a long enough passphrase' } });
  state.users[0].verified_at = new Date();
  state.sent = [];

  const fresh = await call(signup, { method: 'POST', body: { email: 'new@byu.edu', password: 'a long enough passphrase' } });
  const taken = await call(signup, { method: 'POST', body: { email: 'taken@byu.edu', password: 'another passphrase here' } });

  // Identical shape and status, or this endpoint becomes a way to test which
  // addresses have accounts.
  assert.equal(taken.status, fresh.status);
  assert.deepEqual(taken.body, fresh.body);
  assert.equal(state.users.length, 2, 'no second account for the taken address');
  assert.ok(!state.sent.some((m) => m.to === 'taken@byu.edu'), 'and no email to the existing account');
});

test('sign-up is throttled', async () => {
  resetState();
  state.throttled = true;
  const result = await call(signup, { method: 'POST', body: { email: 'a@b.co', password: 'a long enough passphrase' } });
  assert.equal(result.status, 429);
});

// ---------- verify ----------

test('the emailed link verifies the account exactly once', async () => {
  resetState();
  await call(signup, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });
  const token = tokenFrom(state.sent[0].link);

  const first = await call(verify, { method: 'GET', query: { token } });
  assert.equal(first.status, 302);
  assert.match(first.redirect, /\?verified=1$/);
  assert.ok(state.users[0].verified_at);

  const second = await call(verify, { method: 'GET', query: { token } });
  assert.match(second.redirect, /\?verified=expired$/, 'a used link cannot be replayed');
});

test('a junk or missing token is refused', async () => {
  resetState();
  assert.match((await call(verify, { method: 'GET', query: {} })).redirect, /invalid/);
  assert.match((await call(verify, { method: 'GET', query: { token: 'made-up' } })).redirect, /expired/);
});

test('verifying does not hand out a session', async () => {
  resetState();
  await call(signup, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });
  const result = await call(verify, { method: 'GET', query: { token: tokenFrom(state.sent[0].link) } });
  // Email scanners follow links. A session must come from signing in.
  assert.ok(!result.headers['set-cookie']);
  assert.equal(state.sessions.length, 0);
});

// ---------- log in ----------

async function makeVerifiedUser(address, password) {
  const user = await db.createUser(address, await hashPassword(password));
  user.verified_at = new Date();
  return user;
}

test('an unknown address and a wrong password fail identically', async () => {
  resetState();
  await makeVerifiedUser('student@byu.edu', 'a long enough passphrase');

  const wrongPassword = await call(login, { method: 'POST', body: { email: 'student@byu.edu', password: 'not the passphrase' } });
  const unknownEmail = await call(login, { method: 'POST', body: { email: 'nobody@byu.edu', password: 'a long enough passphrase' } });

  assert.equal(wrongPassword.status, 401);
  assert.equal(unknownEmail.status, wrongPassword.status);
  assert.deepEqual(unknownEmail.body, wrongPassword.body);
});

test('an unverified account cannot sign in', async () => {
  resetState();
  await db.createUser('student@byu.edu', await hashPassword('a long enough passphrase'));
  const result = await call(login, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });

  assert.equal(result.status, 403);
  assert.equal(result.body.needsVerification, true);
  assert.equal(state.sessions.length, 0);
});

test('a verified account signs in and gets an HttpOnly session cookie', async () => {
  resetState();
  await makeVerifiedUser('student@byu.edu', 'a long enough passphrase');
  const result = await call(login, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });

  assert.equal(result.status, 200);
  assert.equal(result.body.email, 'student@byu.edu');

  const cookie = String(result.headers['set-cookie']);
  assert.match(cookie, /^cdt_session=/);
  assert.match(cookie, /HttpOnly/, 'script must not be able to read it');
  assert.match(cookie, /SameSite=Lax/);
  assert.match(cookie, /Secure/);
});

test('the session token is stored only as a digest', async () => {
  resetState();
  await makeVerifiedUser('student@byu.edu', 'a long enough passphrase');
  const result = await call(login, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });
  const token = cookieFrom(result).split('=')[1];

  assert.equal(state.sessions.length, 1);
  assert.notEqual(state.sessions[0].tokenHash, token, 'a database leak must not hand over live sessions');
});

test('login is throttled', async () => {
  resetState();
  state.throttled = true;
  const result = await call(login, { method: 'POST', body: { email: 'a@b.co', password: 'whatever it is' } });
  assert.equal(result.status, 429);
});

// ---------- the user's data ----------

async function signedInCookie() {
  await makeVerifiedUser('student@byu.edu', 'a long enough passphrase');
  const result = await call(login, { method: 'POST', body: { email: 'student@byu.edu', password: 'a long enough passphrase' } });
  return cookieFrom(result);
}

test('deadlines are refused without a session', async () => {
  resetState();
  assert.equal((await call(deadlines, { method: 'GET' })).status, 401);
  assert.equal((await call(deadlines, { method: 'PUT', body: { deadlines: [] } })).status, 401);
  assert.equal((await call(deadlines, { method: 'GET', headers: { cookie: 'cdt_session=forged' } })).status, 401);
});

test('deadlines round-trip for the signed-in user', async () => {
  resetState();
  const cookie = await signedInCookie();
  const rows = [{ id: 'canvas:1', title: 'Homework' }];

  const saved = await call(deadlines, { method: 'PUT', headers: { cookie }, body: { deadlines: rows, settings: { showsCompleted: true } } });
  assert.equal(saved.status, 200);

  const loaded = await call(deadlines, { method: 'GET', headers: { cookie } });
  assert.deepEqual(loaded.body.deadlines, rows);
  assert.equal(loaded.body.settings.showsCompleted, true);
});

test('one account cannot read another account’s deadlines', async () => {
  resetState();
  const mine = await signedInCookie();
  await call(deadlines, { method: 'PUT', headers: { cookie: mine }, body: { deadlines: [{ id: 'private' }] } });

  await makeVerifiedUser('roommate@byu.edu', 'a different passphrase');
  const theirs = cookieFrom(await call(login, { method: 'POST', body: { email: 'roommate@byu.edu', password: 'a different passphrase' } }));

  const seen = await call(deadlines, { method: 'GET', headers: { cookie: theirs } });
  assert.deepEqual(seen.body.deadlines, [], 'this is the whole point of putting the data on a server');
});

test('an oversized payload is refused', async () => {
  resetState();
  const cookie = await signedInCookie();
  const huge = Array.from({ length: 2001 }, (_, i) => ({ id: String(i) }));
  assert.equal((await call(deadlines, { method: 'PUT', headers: { cookie }, body: { deadlines: huge } })).status, 413);
});

// ---------- session lifecycle ----------

test('me reports the session, and logout ends it', async () => {
  resetState();
  const cookie = await signedInCookie();

  assert.equal((await call(me, { method: 'GET', headers: { cookie } })).body.user.email, 'student@byu.edu');

  await call(logout, { method: 'POST', headers: { cookie } });
  assert.equal(state.sessions.length, 0);
  assert.equal((await call(me, { method: 'GET', headers: { cookie } })).body.user, null);
});

test('endpoints reject the wrong method', async () => {
  resetState();
  assert.equal((await call(signup, { method: 'GET' })).status, 405);
  assert.equal((await call(login, { method: 'GET' })).status, 405);
  assert.equal((await call(deadlines, { method: 'DELETE' })).status, 405);
});
