// Wiring: state, rendering, and the two import paths.
(function () {
  'use strict';

  const store = CDT;
  const config = (typeof window !== 'undefined' && window.CDT_CONFIG) || {};
  const session = CDT.createSession({ googleClientId: config.GOOGLE_CLIENT_ID });

  // Storage is per-identity, so switching accounts swaps the whole slice.
  let storage = null;

  const state = {
    identity: null,
    deadlines: [],
    settings: Object.assign({}, store.DEFAULT_SETTINGS),
    view: 'list',
    calendarMode: 'month',
    anchor: new Date(),
    selected: new Date(),
    banners: []
  };

  const account = CDT.createAccount();

  function adoptIdentity(identity) {
    state.identity = identity;
    storage = CDT.createStorage(null, session.namespaceFor(identity));
    state.deadlines = storage.loadDeadlines();
    state.settings = storage.loadSettings();
    state.banners = [];
    state.view = 'list';
    render();
  }

  // An account keeps its data on the server, so it is private rather than
  // merely separate. The local copy is a cache, so the list still works offline.
  async function adoptAccount(user) {
    const identity = { kind: 'account', id: user.email, email: user.email, name: user.email };
    const cache = CDT.createStorage(null, session.namespaceFor(identity));
    const remote = CDT.createServerStorage(cache);

    state.identity = identity;
    storage = remote;
    state.deadlines = remote.loadDeadlines();
    state.settings = Object.assign({}, store.DEFAULT_SETTINGS, remote.loadSettings());
    state.banners = [];
    state.view = 'list';
    render();

    try {
      await remote.pull();
      state.deadlines = remote.loadDeadlines();
      state.settings = Object.assign({}, store.DEFAULT_SETTINGS, remote.loadSettings());
    } catch (error) {
      banner('error', 'Working from the local copy', error.message);
    }
    render();
  }

  // A page loaded from an extension origin has host_permissions, so its fetches
  // are exempt from CORS and can call Canvas directly. A page served over http
  // cannot, so it routes through the same-origin proxy function instead. A page
  // opened from disk has neither, and cannot sync at all.
  const isExtension = typeof chrome !== 'undefined' && !!(chrome.runtime && chrome.runtime.id);
  const isServed = location.protocol === 'http:' || location.protocol === 'https:';
  const canvasProxy = !isExtension && isServed ? '/api/canvas' : null;
  const canSync = isExtension || !!canvasProxy;

  function canvasClient(host, token) {
    return CDT.createClient(host, token, { proxy: canvasProxy });
  }

  const $ = (id) => document.getElementById(id);
  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };

  // Small line icons per item type. Static markup, so innerHTML is safe here —
  // nothing user-supplied ever reaches it.
  const TYPE_ICONS = {
    assignment: '<path d="M4 2h5l3 3v9H4z"/><path d="M9 2v3h3"/>',
    quiz: '<path d="M3 4.5l1.5 1.5L7 3.5"/><path d="M3 11l1.5 1.5L7 10"/><path d="M9 5h4"/><path d="M9 11.5h4"/>',
    discussion: '<path d="M2 3h9v6H6l-3 2.5V9H2z"/><path d="M13 6h1v6h-1l-2 1.5V12"/>',
    exam: '<path d="M8 2l6 3-6 3-6-3z"/><path d="M4 7v4c0 1 2 2 4 2s4-1 4-2V7"/>',
    other: '<circle cx="8" cy="8" r="5"/>'
  };

  function typeIcon(type) {
    const span = document.createElement('span');
    span.innerHTML =
      '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      (TYPE_ICONS[type] || TYPE_ICONS.other) + '</svg>';
    return span.firstChild;
  }

  function pill(className, text, type) {
    const node = el('span', 'pill ' + className);
    if (type) node.appendChild(typeIcon(type));
    node.appendChild(document.createTextNode(text));
    return node;
  }

  function save() {
    if (!storage) return;
    storage.saveDeadlines(state.deadlines);
    storage.saveSettings(state.settings);
  }

  function banner(kind, title, message) {
    state.banners.push({ kind, title, message });
    render();
  }

  function visibleDeadlines() {
    return state.settings.showsCompleted
      ? state.deadlines
      : state.deadlines.filter((d) => !d.isCompleted);
  }

  // ---------- rendering ----------

  const timeFormat = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
  const dayFormat = new Intl.DateTimeFormat(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
  const monthFormat = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' });
  const longDayFormat = new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'long', day: 'numeric' });

  function dayTitle(date, now) {
    const key = store.countsKey;
    if (key(date) === key(now)) return 'Today';
    const tomorrow = new Date(now); tomorrow.setDate(tomorrow.getDate() + 1);
    if (key(date) === key(tomorrow)) return 'Tomorrow';
    const yesterday = new Date(now); yesterday.setDate(yesterday.getDate() - 1);
    if (key(date) === key(yesterday)) return 'Yesterday';
    return dayFormat.format(date);
  }

  function deadlineRow(deadline, now) {
    const overdue = store.isOverdue(deadline, now);
    const row = el('div', 'deadline' + (deadline.isCompleted ? ' done' : '') + (overdue ? ' overdue' : ''));

    const check = el('input', 'check');
    check.type = 'checkbox';
    check.checked = !!deadline.isCompleted;
    check.setAttribute('aria-label', (deadline.isCompleted ? 'Mark not done: ' : 'Mark done: ') + deadline.title);
    check.addEventListener('change', function () {
      state.deadlines = store.setCompleted(state.deadlines, deadline.id, check.checked);
      save();
      render();
    });

    const body = el('div', 'body');
    if (deadline.url) {
      const link = el('a', 'title', deadline.title);
      link.href = deadline.url;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      body.appendChild(link);
    } else {
      body.appendChild(el('span', 'title', deadline.title));
    }
    const meta = el('div', 'meta');
    meta.appendChild(pill('course', deadline.courseCode || deadline.courseName, deadline.type));
    meta.appendChild(pill(deadline.source, deadline.source === 'canvas' ? 'Canvas' : 'Learning Suite'));
    body.appendChild(meta);

    const when = el('div', 'when');
    when.appendChild(document.createTextNode(timeFormat.format(new Date(deadline.dueDate))));
    if (overdue) when.appendChild(el('span', 'flag', 'Overdue'));

    row.append(check, body, when);
    return row;
  }

  function renderList(container, deadlines, now, emptyMessage) {
    container.innerHTML = '';
    const days = store.byDay(deadlines);
    if (!days.length) {
      container.appendChild(el('p', 'empty', emptyMessage));
      return;
    }
    for (const day of days) {
      const heading = el('h2', 'day-heading' + (day.date < store.startOfDay(now) ? ' past' : ''));
      heading.appendChild(el('span', null, dayTitle(day.date, now)));
      const outstanding = day.deadlines.filter((d) => !d.isCompleted).length;
      if (outstanding) heading.appendChild(el('span', 'n', String(outstanding)));
      container.appendChild(heading);
      for (const deadline of day.deadlines) container.appendChild(deadlineRow(deadline, now));
    }
  }

  function monthGrid(anchor) {
    const first = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
    const lead = first.getDay();
    const start = new Date(first); start.setDate(1 - lead);
    const daysInMonth = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0).getDate();
    const cells = Math.ceil((lead + daysInMonth) / 7) * 7;
    return Array.from({ length: cells }, function (_, i) {
      const date = new Date(start); date.setDate(start.getDate() + i); return date;
    });
  }

  function weekGrid(anchor) {
    const start = new Date(anchor); start.setDate(anchor.getDate() - anchor.getDay());
    return Array.from({ length: 7 }, function (_, i) {
      const date = new Date(start); date.setDate(start.getDate() + i); return date;
    });
  }

  function renderCalendar(now) {
    const grid = $('calendar-grid');
    grid.innerHTML = '';
    const visible = visibleDeadlines();
    const counts = store.countsByDay(visible, state.settings.showsCompleted);
    const overdueDays = new Set(
      visible.filter((d) => store.isOverdue(d, now)).map((d) => store.countsKey(d.dueDate))
    );

    let dates = [];
    if (state.calendarMode === 'month') {
      $('cal-title').textContent = monthFormat.format(state.anchor);
      dates = monthGrid(state.anchor);
    } else if (state.calendarMode === 'week') {
      dates = weekGrid(state.anchor);
      $('cal-title').textContent = dayFormat.format(dates[0]) + ' – ' + dayFormat.format(dates[6]);
    } else {
      $('cal-title').textContent = longDayFormat.format(state.selected);
    }

    if (dates.length) {
      const wrapper = el('div', 'grid');
      const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      for (const name of weekdays) wrapper.appendChild(el('div', 'weekday', name));

      for (const date of dates) {
        const key = store.countsKey(date);
        const count = counts.get(key) || 0;
        const overdue = overdueDays.has(key);
        const cell = el('button', 'cell');
        if (state.calendarMode === 'month' && date.getMonth() !== state.anchor.getMonth()) cell.classList.add('outside');
        if (key === store.countsKey(now)) cell.classList.add('today');
        if (key === store.countsKey(state.selected)) cell.classList.add('selected');

        cell.appendChild(el('span', 'num', String(date.getDate())));
        // Dots up to three, then a number: past three, nobody counts dots.
        if (count > 0 && count <= 3) {
          const dots = el('div', 'dots');
          for (let i = 0; i < count; i += 1) dots.appendChild(el('span', 'dot' + (overdue ? ' overdue' : '')));
          cell.appendChild(dots);
        } else if (count > 3) {
          cell.appendChild(el('span', 'count' + (overdue ? ' overdue' : ''), String(count)));
        }

        cell.setAttribute('aria-label',
          longDayFormat.format(date) + ', ' +
          (count === 0 ? 'nothing due' : count + (count === 1 ? ' deadline' : ' deadlines') + (overdue ? ', some overdue' : '')));
        cell.addEventListener('click', function () {
          state.selected = date;
          if (date.getMonth() !== state.anchor.getMonth()) state.anchor = new Date(date);
          render();
        });
        wrapper.appendChild(cell);
      }
      grid.appendChild(wrapper);
    }

    const onDay = visible.filter((d) => store.countsKey(d.dueDate) === store.countsKey(state.selected));
    renderList($('calendar-day-list'), onDay, now,
      'Nothing due on ' + longDayFormat.format(state.selected) + '.');
  }

  function renderSettings() {
    $('canvas-host').value = state.settings.canvasHost;
    const token = state.settings.canvasToken;
    $('canvas-status').textContent = token
      ? 'Connected' + (state.settings.canvasName ? ' as ' + state.settings.canvasName : '') + '.'
      : (canSync
        ? 'Not connected.'
        : 'Not connected — opened from disk, so live sync is unavailable. Load as a Chrome extension, or open the deployed site.');

    const lsCount = state.deadlines.filter((d) => d.source === 'learningSuite').length;
    $('ls-status').textContent = lsCount
      ? lsCount + ' item' + (lsCount === 1 ? '' : 's') + ' imported.'
      : 'Nothing imported yet.';

    const canvasCount = state.deadlines.filter((d) => d.source === 'canvas').length;
    $('data-summary').textContent =
      state.deadlines.length + ' cached (' + canvasCount + ' Canvas, ' + lsCount + ' Learning Suite). ' +
      'Stored in this browser only.';
  }

  // A glance at the shape of the week, above the list.
  function renderStats(now) {
    const container = $('stats');
    const outstanding = state.deadlines.filter((d) => !d.isCompleted);
    container.hidden = state.view !== 'list' || !state.deadlines.length;
    if (container.hidden) return;

    const startToday = store.startOfDay(now);
    const endToday = new Date(startToday); endToday.setDate(endToday.getDate() + 1);
    const endWeek = new Date(startToday); endWeek.setDate(endWeek.getDate() + 7);

    const overdue = outstanding.filter((d) => new Date(d.dueDate) < now).length;
    const today = outstanding.filter(function (d) {
      const due = new Date(d.dueDate);
      return due >= startToday && due < endToday;
    }).length;
    const week = outstanding.filter(function (d) {
      const due = new Date(d.dueDate);
      return due >= startToday && due < endWeek;
    }).length;

    container.innerHTML = '';
    [
      { n: overdue, k: 'Overdue', overdue: overdue > 0 },
      { n: today, k: 'Due today' },
      { n: week, k: 'Next 7 days' }
    ].forEach(function (entry) {
      const card = el('div', 'stat' + (entry.overdue ? ' is-overdue' : ''));
      card.appendChild(el('span', 'n', String(entry.n)));
      card.appendChild(el('span', 'k', entry.k));
      container.appendChild(card);
    });
  }

  function render() {
    const now = new Date();

    // No identity yet: show only the sign-in gate.
    const signedIn = !!state.identity;
    $('sign-in').hidden = signedIn;
    $('app').hidden = !signedIn;
    document.querySelector('.bar').hidden = !signedIn;
    $('account').hidden = !signedIn;
    if (signedIn) {
      $('account-name').textContent = state.identity.name;
      $('account-name').title = state.identity.email || state.identity.name;
    }
    if (!signedIn) { $('stats').hidden = true; return; }

    document.querySelectorAll('.tab').forEach(function (tab) {
      const active = tab.dataset.view === state.view;
      tab.setAttribute('aria-selected', String(active));
    });
    $('view-list').hidden = state.view !== 'list';
    $('view-calendar').hidden = state.view !== 'calendar';
    $('view-settings').hidden = state.view !== 'settings';
    document.querySelectorAll('.seg').forEach(function (seg) {
      seg.classList.toggle('is-active', seg.dataset.mode === state.calendarMode);
    });
    $('shows-completed').checked = !!state.settings.showsCompleted;

    const banners = $('banners');
    banners.innerHTML = '';
    for (const item of state.banners) {
      const node = el('div', 'banner' + (item.kind === 'ok' ? ' ok' : ''));
      node.appendChild(el('h3', null, item.title));
      node.appendChild(el('p', null, item.message));
      banners.appendChild(node);
    }

    renderStats(now);

    if (state.view === 'list') {
      renderList($('view-list'), visibleDeadlines(), now,
        state.deadlines.length
          ? 'Nothing outstanding. Turn on “Show completed” to see finished work.'
          : 'Nothing here yet. Connect Canvas or import Learning Suite in Settings.');
    } else if (state.view === 'calendar') {
      renderCalendar(now);
    } else {
      renderSettings();
    }
  }

  // ---------- actions ----------

  async function syncCanvas() {
    const settings = state.settings;
    if (!settings.canvasToken) {
      banner('error', 'Canvas not connected', 'Add your access token in Settings.');
      return;
    }
    state.banners = [];
    try {
      const client = canvasClient(settings.canvasHost, settings.canvasToken);
      const items = await client.fetchDeadlines();
      const merged = store.merge(state.deadlines, items, 'canvas');
      state.deadlines = merged.deadlines;
      save();
      banner('ok', 'Canvas synced', items.length + ' deadlines read from Canvas.');
    } catch (error) {
      banner('error', 'Canvas sync failed', error.message || String(error));
    }
  }

  function importLearningSuite() {
    const html = $('ls-html').value.trim();
    state.banners = [];
    if (!html) {
      banner('error', 'Nothing to read', 'Paste the page source from your Learning Suite assignments page first.');
      return;
    }
    try {
      const parser = CDT.createParser();
      const items = parser.parse(html);
      if (!items.length) {
        banner('ok', 'Nothing due', 'Learning Suite reported no assignments on that page.');
        return;
      }
      const merged = store.merge(state.deadlines, items, 'learningSuite');
      state.deadlines = merged.deadlines;
      save();
      $('ls-html').value = '';
      banner('ok', 'Learning Suite imported', items.length + ' assignments read from the pasted page.');
      state.view = 'list';
    } catch (error) {
      banner('error', 'Could not read that page', error.message || String(error));
    }
  }

  // ---------- events ----------

  document.querySelectorAll('.tab').forEach(function (tab) {
    tab.addEventListener('click', function () { state.view = tab.dataset.view; state.banners = []; render(); });
  });
  document.querySelectorAll('.seg').forEach(function (seg) {
    seg.addEventListener('click', function () { state.calendarMode = seg.dataset.mode; render(); });
  });

  $('shows-completed').addEventListener('change', function (event) {
    state.settings.showsCompleted = event.target.checked;
    save();
    render();
  });

  $('refresh').addEventListener('click', syncCanvas);

  $('cal-prev').addEventListener('click', function () { stepCalendar(-1); });
  $('cal-next').addEventListener('click', function () { stepCalendar(1); });
  $('cal-today').addEventListener('click', function () {
    state.anchor = new Date(); state.selected = new Date(); render();
  });

  function stepCalendar(amount) {
    if (state.calendarMode === 'month') {
      state.anchor = new Date(state.anchor.getFullYear(), state.anchor.getMonth() + amount, 1);
      if (state.selected.getMonth() !== state.anchor.getMonth()) state.selected = new Date(state.anchor);
    } else if (state.calendarMode === 'week') {
      state.anchor = new Date(state.anchor); state.anchor.setDate(state.anchor.getDate() + amount * 7);
      state.selected = new Date(state.selected); state.selected.setDate(state.selected.getDate() + amount * 7);
    } else {
      state.selected = new Date(state.selected); state.selected.setDate(state.selected.getDate() + amount);
      state.anchor = new Date(state.selected);
    }
    render();
  }

  $('canvas-connect').addEventListener('click', async function () {
    const host = $('canvas-host').value.trim() || 'byu.instructure.com';
    const token = $('canvas-token').value.trim();
    state.banners = [];
    if (!token) { banner('error', 'No token', 'Paste a Canvas access token first.'); return; }
    try {
      // Verify before storing, so a typo fails now rather than silently later.
      const name = await canvasClient(host, token).verifyToken();
      state.settings.canvasHost = host;
      state.settings.canvasToken = token;
      state.settings.canvasName = name;
      save();
      $('canvas-token').value = '';
      banner('ok', 'Canvas connected', 'Signed in as ' + name + '.');
      await syncCanvas();
    } catch (error) {
      banner('error', 'Could not connect', error.message || String(error));
    }
  });

  $('canvas-forget').addEventListener('click', function () {
    delete state.settings.canvasToken;
    delete state.settings.canvasName;
    state.deadlines = state.deadlines.filter((d) => d.source !== 'canvas');
    save();
    state.banners = [];
    render();
  });

  $('ls-import').addEventListener('click', importLearningSuite);
  $('ls-forget').addEventListener('click', function () {
    state.deadlines = state.deadlines.filter((d) => d.source !== 'learningSuite');
    save();
    render();
  });

  $('export').addEventListener('click', function () {
    const blob = new Blob([JSON.stringify(state.deadlines, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'deadlines.json';
    link.click();
    URL.revokeObjectURL(link.href);
  });

  $('erase').addEventListener('click', function () {
    const who = state.identity ? state.identity.name : 'this profile';
    if (!confirm('Erase ' + who + '\u2019s cached deadlines, Canvas token, and settings from this browser?')) return;
    state.deadlines = [];
    state.settings = Object.assign({}, store.DEFAULT_SETTINGS);
    if (storage) storage.erase();
    state.banners = [];
    render();
  });

  // ---------- sign in ----------

  function signInError(message) {
    $('signin-error').textContent = message || '';
  }

  $('signin-chrome').hidden = !session.available.chrome;
  $('signin-google').hidden = !session.available.google;

  $('use-chrome').addEventListener('click', function () {
    signInError('');
    session.signInWithChrome().then(adoptIdentity).catch(function (error) {
      signInError(error.message);
    });
  });

  $('use-local').addEventListener('click', function () {
    signInError('');
    try {
      adoptIdentity(session.signInLocally($('local-name').value));
    } catch (error) {
      signInError(error.message);
    }
  });

  $('local-name').addEventListener('keydown', function (event) {
    if (event.key === 'Enter') $('use-local').click();
  });

  if (session.available.google) {
    session.signInWithGoogle($('google-button')).then(adoptIdentity).catch(function (error) {
      signInError(error.message);
    });
  }

  $('sign-out').addEventListener('click', function () {
    const wasAccount = state.identity && state.identity.kind === 'account';
    session.signOut();
    state.identity = null;
    storage = null;
    state.deadlines = [];
    state.settings = Object.assign({}, store.DEFAULT_SETTINGS);
    signInError('');
    render();
    if (wasAccount) account.signOut().catch(function () { /* the cookie expires anyway */ });
  });

  // Accounts only exist where the API does.
  $('signin-account').hidden = !isServed;
  $('signin-note').textContent = isServed
    ? 'An account keeps your deadlines on the server, so nobody else at this computer can read them. '
      + 'The Chrome and profile options keep everything in this browser instead: separate per person, but readable '
      + 'from the developer console by anyone using this machine.'
    : 'Everything is stored in this browser: separate per person, but readable from the developer console by anyone '
      + 'using this computer. Open the deployed site to use an account, which keeps your data on the server instead.';

  showVerificationOutcome();

  function showVerificationOutcome() {
    const outcome = new URLSearchParams(location.search).get('verified');
    if (!outcome) return;
    const note = $('verified-note');
    note.hidden = false;
    if (outcome === '1') {
      note.textContent = 'Email confirmed. Sign in below.';
      note.classList.remove('bad');
    } else if (outcome === 'expired') {
      note.textContent = 'That link has already been used or has expired. Sign in, or send a new one.';
      note.classList.add('bad');
    } else {
      note.textContent = 'That verification link was not valid.';
      note.classList.add('bad');
    }
    history.replaceState(null, '', location.pathname);
  }

  function accountBusy(busy) {
    ['do-signin', 'do-signup', 'do-resend'].forEach(function (id) {
      const node = $(id);
      if (node) node.disabled = busy;
    });
  }

  function credentials() {
    return { email: $('account-email').value.trim(), password: $('account-password').value };
  }

  $('do-signin').addEventListener('click', async function () {
    signInError('');
    $('resend-row').hidden = true;
    accountBusy(true);
    try {
      const { email } = credentials();
      const user = await account.signIn(email, credentials().password);
      $('account-password').value = '';
      await adoptAccount(user);
    } catch (error) {
      signInError(error.message);
      if (error.needsVerification) $('resend-row').hidden = false;
    } finally {
      accountBusy(false);
    }
  });

  $('do-signup').addEventListener('click', async function () {
    signInError('');
    accountBusy(true);
    try {
      const { email, password } = credentials();
      const result = await account.signUp(email, password);
      $('account-password').value = '';
      const note = $('verified-note');
      note.hidden = false;
      note.classList.remove('bad');
      note.textContent = result.message;
      $('resend-row').hidden = false;
    } catch (error) {
      signInError(error.message);
    } finally {
      accountBusy(false);
    }
  });

  $('do-resend').addEventListener('click', async function () {
    signInError('');
    accountBusy(true);
    try {
      const result = await account.resendVerification(credentials().email);
      const note = $('verified-note');
      note.hidden = false;
      note.classList.remove('bad');
      note.textContent = result.message;
    } catch (error) {
      signInError(error.message);
    } finally {
      accountBusy(false);
    }
  });

  $('account-password').addEventListener('keydown', function (event) {
    if (event.key === 'Enter') $('do-signin').click();
  });

  const existing = session.current();
  if (existing && existing.kind !== 'account') {
    adoptIdentity(existing);
  } else {
    render();
    // A session cookie outlives a reload, so check for one before asking again.
    if (isServed) {
      account.me().then(function (user) {
        if (user) adoptAccount(user);
      }).catch(function () { /* no API here; the other sign-in options still work */ });
    }
  }

  if (!canSync && state.settings.canvasToken) {
    banner('error', 'Live sync unavailable here',
      'Canvas refuses direct calls from web pages, and this page was opened from disk rather than served. ' +
      'Load this folder as a Chrome extension, or open the deployed site; cached deadlines and ' +
      'Learning Suite import still work either way.');
  }
}());
