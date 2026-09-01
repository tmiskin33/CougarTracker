// Talks to the account API, and keeps the signed-in user's data on the server
// with a local copy for offline reading.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.CDT = Object.assign(root.CDT || {}, factory());
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  async function request(path, options) {
    let response;
    try {
      response = await fetch(path, Object.assign({
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin'
      }, options || {}));
    } catch (_) {
      throw new Error('Could not reach the server. Check your connection.');
    }

    // A static deployment has no functions, so the router answers with HTML.
    const type = response.headers.get('content-type') || '';
    if (!type.includes('json')) {
      throw new Error('This site was deployed without the account API, so accounts are unavailable here.');
    }

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(payload.error || 'Something went wrong.');
      error.status = response.status;
      error.needsVerification = !!payload.needsVerification;
      throw error;
    }
    return payload;
  }

  function createAccount() {
    return {
      me() {
        return request('/api/auth/me', { method: 'GET' }).then((r) => r.user);
      },
      signUp(email, password) {
        return request('/api/auth/signup', { method: 'POST', body: JSON.stringify({ email, password }) });
      },
      signIn(email, password) {
        return request('/api/auth/login', { method: 'POST', body: JSON.stringify({ email, password }) });
      },
      signOut() {
        return request('/api/auth/logout', { method: 'POST' });
      },
      resendVerification(email) {
        return request('/api/auth/resend', { method: 'POST', body: JSON.stringify({ email }) });
      }
    };
  }

  // Same shape as the local storage adapter, so the app does not care which it
  // has. `pull` must run before the first render; writes go to the local copy
  // immediately and to the server on a short debounce.
  function createServerStorage(cache) {
    let deadlines = cache ? cache.loadDeadlines() : [];
    let settings = cache ? cache.loadSettings() : {};
    let timer = null;
    let pending = false;

    function push() {
      pending = true;
      if (timer) clearTimeout(timer);
      timer = setTimeout(function () {
        timer = null;
        const body = JSON.stringify({ deadlines: deadlines, settings: settings });
        request('/api/deadlines', { method: 'PUT', body: body })
          .then(function () { pending = false; })
          .catch(function () { /* the local copy still holds it; the next write retries */ });
      }, 600);
    }

    return {
      prefix: 'server',
      hasPendingWrites() { return pending; },
      async pull() {
        const remote = await request('/api/deadlines', { method: 'GET' });
        deadlines = Array.isArray(remote.deadlines) ? remote.deadlines : [];
        settings = remote.settings && typeof remote.settings === 'object' ? remote.settings : {};
        if (cache) { cache.saveDeadlines(deadlines); cache.saveSettings(settings); }
      },
      loadDeadlines() { return deadlines; },
      loadSettings() { return settings; },
      saveDeadlines(next) {
        deadlines = next;
        if (cache) cache.saveDeadlines(next);
        push();
      },
      saveSettings(next) {
        settings = next;
        if (cache) cache.saveSettings(next);
        push();
      },
      erase() {
        deadlines = [];
        settings = {};
        if (cache) cache.erase();
        push();
      }
    };
  }

  return { createAccount, createServerStorage };
}));
