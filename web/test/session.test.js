'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { createSession, readGoogleCredential } = require('../js/session.js');
const store = require('../js/store.js');

function memory() {
  return {
    data: {},
    getItem(key) { return Object.prototype.hasOwnProperty.call(this.data, key) ? this.data[key] : null; },
    setItem(key, value) { this.data[key] = String(value); },
    removeItem(key) { delete this.data[key]; }
  };
}

test('a local profile is remembered across reloads', () => {
  const backing = memory();
  const first = createSession({ storage: backing, chrome: null });
  const identity = first.signInLocally('Tanner');

  const reopened = createSession({ storage: backing, chrome: null });
  assert.deepEqual(reopened.current(), identity);
});

test('signing out forgets the identity', () => {
  const backing = memory();
  const session = createSession({ storage: backing, chrome: null });
  session.signInLocally('Tanner');
  session.signOut();
  assert.equal(session.current(), null);
});

test('a blank profile name is refused', () => {
  const session = createSession({ storage: memory(), chrome: null });
  assert.throws(() => session.signInLocally('   '));
});

test('two people on one browser get separate storage', () => {
  const backing = memory();
  const session = createSession({ storage: backing, chrome: null });

  const tanner = session.signInLocally('Tanner');
  const tannerStore = store.createStorage(backing, session.namespaceFor(tanner));
  tannerStore.saveSettings({ canvasToken: 'tanner-token', showsCompleted: true });
  tannerStore.saveDeadlines([{ id: 'a' }]);

  const roommate = session.signInLocally('Roommate');
  const roommateStore = store.createStorage(backing, session.namespaceFor(roommate));

  assert.equal(roommateStore.loadSettings().canvasToken, undefined, 'no token leaks across profiles');
  assert.deepEqual(roommateStore.loadDeadlines(), [], 'no deadlines leak across profiles');
  assert.equal(tannerStore.loadSettings().canvasToken, 'tanner-token', 'and the first profile is intact');
});

test('erasing one profile leaves the other alone', () => {
  const backing = memory();
  const session = createSession({ storage: backing, chrome: null });

  const a = store.createStorage(backing, session.namespaceFor(session.signInLocally('A')));
  const b = store.createStorage(backing, session.namespaceFor(session.signInLocally('B')));
  a.saveDeadlines([{ id: 'a' }]);
  b.saveDeadlines([{ id: 'b' }]);

  a.erase();
  assert.deepEqual(a.loadDeadlines(), []);
  assert.deepEqual(b.loadDeadlines(), [{ id: 'b' }]);
});

test('the namespace does not carry the email address around', () => {
  const session = createSession({ storage: memory(), chrome: null });
  const namespace = session.namespaceFor({ kind: 'google', id: '123', email: 'someone@byu.edu' });
  assert.ok(!namespace.includes('someone'));
  assert.ok(!namespace.includes('byu.edu'));
});

test('the same identity always resolves to the same namespace', () => {
  const session = createSession({ storage: memory(), chrome: null });
  const identity = { kind: 'chrome', id: 'abc123', email: 'x@y.z' };
  assert.equal(session.namespaceFor(identity), session.namespaceFor(Object.assign({}, identity)));
});

test('Chrome sign-in reports the profile account', async () => {
  const chromeApi = {
    runtime: { id: 'ext' },
    identity: {
      getProfileUserInfo(_options, callback) { callback({ id: 'chrome-user-1', email: 'student@byu.edu' }); }
    }
  };
  const session = createSession({ storage: memory(), chrome: chromeApi });
  assert.equal(session.available.chrome, true);

  const identity = await session.signInWithChrome();
  assert.equal(identity.kind, 'chrome');
  assert.equal(identity.email, 'student@byu.edu');
});

test('Chrome sign-in fails clearly when Chrome has no account', async () => {
  const chromeApi = {
    runtime: { id: 'ext' },
    identity: { getProfileUserInfo(_options, callback) { callback({ id: '', email: '' }); } }
  };
  const session = createSession({ storage: memory(), chrome: chromeApi });
  await assert.rejects(() => session.signInWithChrome(), /not signed in/i);
});

test('Chrome sign-in is unavailable outside an extension', async () => {
  const session = createSession({ storage: memory(), chrome: null });
  assert.equal(session.available.chrome, false);
  await assert.rejects(() => session.signInWithChrome(), /extension/i);
});

test('a Google credential is read for its account, not trusted as proof', () => {
  const payload = { sub: '10769150350006150715113082367', email: 'student@byu.edu', name: 'A Student' };
  const jwt = 'header.' + Buffer.from(JSON.stringify(payload)).toString('base64url') + '.signature';

  const identity = readGoogleCredential(jwt);
  assert.equal(identity.kind, 'google');
  assert.equal(identity.id, payload.sub);
  assert.equal(identity.email, 'student@byu.edu');
});

test('a malformed Google credential is rejected rather than half-read', () => {
  assert.equal(readGoogleCredential('not-a-jwt'), null);
  assert.equal(readGoogleCredential('a.' + Buffer.from('{}').toString('base64url') + '.c'), null);
});
