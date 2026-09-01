// Who is using the app, and which slice of storage is theirs.
//
// Three ways to establish an identity, tried in the order that needs the least
// setup:
//
//   1. Chrome profile  — extension only. chrome.identity reports the account
//      already signed in to Chrome, so there is nothing to configure and
//      nothing to type.
//   2. Google sign-in  — any browser, but needs a Google OAuth client ID in
//      config.js. Uses Google Identity Services.
//   3. A local profile — a name you pick. No account, no network, works
//      everywhere.
//
// What this is and is not: it decides *which* stored data you see, and labels
// it. It does not protect that data. Everything lives in this browser's local
// storage, readable from the developer console whoever is signed in. Only
// server-side storage can make one person's deadlines unreadable to someone
// else at the same machine — see README.md.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./ls-parse.js'));
  else root.CDT = Object.assign(root.CDT || {}, factory(root.CDT));
}(typeof self !== 'undefined' ? self : this, function (lib) {
  'use strict';

  const stableId = lib.stableId;
  const CURRENT_KEY = 'cougar.session.v1';

  function namespaceFor(identity) {
    if (!identity) return '';
    // Hashed so the storage key does not carry an email address around.
    return 'u.' + stableId(identity.kind + ':' + identity.id) + '.';
  }

  // A Google credential is a JWT. Reading its payload is enough to know which
  // account to show and which namespace to use. It is deliberately NOT
  // verified: with no server there is nothing to protect, and treating an
  // unverified claim as proof of anything would be worse than not checking.
  function readGoogleCredential(jwt) {
    const parts = String(jwt).split('.');
    if (parts.length < 2) return null;
    try {
      const padded = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const json = decodeURIComponent(
        atob(padded + '==='.slice((padded.length + 3) % 4))
          .split('')
          .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
          .join('')
      );
      const payload = JSON.parse(json);
      if (!payload.sub) return null;
      return {
        kind: 'google',
        id: payload.sub,
        email: payload.email || null,
        name: payload.name || payload.email || 'Google account'
      };
    } catch (_) {
      return null;
    }
  }

  function createSession(options) {
    const opts = options || {};
    const store = opts.storage || (typeof localStorage !== 'undefined' ? localStorage : null);
    const clientId = opts.googleClientId || null;
    const chromeApi = opts.chrome !== undefined
      ? opts.chrome
      : (typeof chrome !== 'undefined' ? chrome : null);

    const hasChromeIdentity = !!(chromeApi && chromeApi.identity && chromeApi.runtime && chromeApi.runtime.id);
    const hasGoogle = !!clientId;

    function current() {
      if (!store) return null;
      try {
        const raw = store.getItem(CURRENT_KEY);
        if (!raw) return null;
        const identity = JSON.parse(raw);
        return identity && identity.id ? identity : null;
      } catch (_) {
        return null;
      }
    }

    function remember(identity) {
      if (store) {
        try { store.setItem(CURRENT_KEY, JSON.stringify(identity)); } catch (_) { /* private mode */ }
      }
      return identity;
    }

    function signOut() {
      if (store) {
        try { store.removeItem(CURRENT_KEY); } catch (_) { /* ignore */ }
      }
    }

    // Reports the account Chrome itself is signed in as. No OAuth screen, no
    // configuration — but it comes back empty when nobody is signed in to
    // Chrome, which is a normal outcome rather than an error.
    function signInWithChrome() {
      return new Promise(function (resolve, reject) {
        if (!hasChromeIdentity) {
          reject(new Error('Chrome accounts are only available when this is loaded as an extension.'));
          return;
        }
        chromeApi.identity.getProfileUserInfo({ accountStatus: 'ANY' }, function (info) {
          if (!info || !info.id) {
            reject(new Error('Chrome is not signed in to an account. Sign in to Chrome, or use a local profile.'));
            return;
          }
          resolve(remember({
            kind: 'chrome',
            id: info.id,
            email: info.email || null,
            name: info.email || 'Chrome profile'
          }));
        });
      });
    }

    function loadGoogleScript() {
      return new Promise(function (resolve, reject) {
        if (typeof document === 'undefined') { reject(new Error('No document.')); return; }
        if (root.google && root.google.accounts && root.google.accounts.id) { resolve(); return; }
        const script = document.createElement('script');
        script.src = 'https://accounts.google.com/gsi/client';
        script.async = true;
        script.onload = resolve;
        script.onerror = function () { reject(new Error('Could not load Google sign-in.')); };
        document.head.appendChild(script);
      });
    }

    function signInWithGoogle(buttonContainer) {
      return loadGoogleScript().then(function () {
        return new Promise(function (resolve, reject) {
          if (!hasGoogle) { reject(new Error('No Google client ID is configured (see config.js).')); return; }
          root.google.accounts.id.initialize({
            client_id: clientId,
            callback: function (response) {
              const identity = readGoogleCredential(response && response.credential);
              if (!identity) { reject(new Error('Google returned something unreadable.')); return; }
              resolve(remember(identity));
            }
          });
          if (buttonContainer) {
            buttonContainer.innerHTML = '';
            root.google.accounts.id.renderButton(buttonContainer, { theme: 'outline', size: 'large' });
          }
          root.google.accounts.id.prompt();
        });
      });
    }

    function signInLocally(name) {
      const trimmed = String(name || '').trim();
      if (!trimmed) throw new Error('Pick a name for this profile.');
      return remember({
        kind: 'local',
        id: trimmed.toLowerCase(),
        email: null,
        name: trimmed
      });
    }

    return {
      current, signOut, signInWithChrome, signInWithGoogle, signInLocally,
      namespaceFor,
      available: {
        chrome: hasChromeIdentity,
        google: hasGoogle,
        local: true
      }
    };
  }

  return { createSession, namespaceFor, readGoogleCredential };
}));
