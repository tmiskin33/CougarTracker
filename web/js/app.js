// Wiring: state, rendering, and the two import paths.
(function () {
  'use strict';

  const { parseHTML } = CDT;
  const store = CDT;
  const storage = CDT.createStorage();

  const state = {
    deadlines: storage.loadDeadlines(),
    settings: storage.loadSettings(),
    view: 'list',
    calendarMode: 'month',
    anchor: new Date(),
    selected: new Date(),
    banners: []
  };

  // A page loaded from an extension origin has host_permissions, so its fetches
  // are exempt from CORS. A plain page does not, and Canvas will refuse it.
  const isExtension = typeof chrome !== 'undefined' && !!(chrome.runtime && chrome.runtime.id);

  const $ = (id) => document.getElementById(id);
  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };

  function save() {
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
    const label = deadline.courseCode || deadline.courseName;
    const sourceName = deadline.source === 'canvas' ? 'Canvas' : 'Learning Suite';
    body.appendChild(el('div', 'meta', label + ' · ' + sourceName + ' · ' + deadline.type));

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
      if (outstanding) heading.appendChild(el('span', null, String(outstanding)));
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

    $('calendar-day-heading').textContent = longDayFormat.format(state.selected);
    const onDay = visible.filter((d) => store.countsKey(d.dueDate) === store.countsKey(state.selected));
    renderList($('calendar-day-list'), onDay, now, 'Nothing due on this day.');
  }

  function renderSettings() {
    $('canvas-host').value = state.settings.canvasHost;
    const token = state.settings.canvasToken;
    $('canvas-status').textContent = token
      ? 'Connected' + (state.settings.canvasName ? ' as ' + state.settings.canvasName : '') + '.'
      : (isExtension ? 'Not connected.' : 'Not connected — live sync needs the Chrome extension (see README).');

    const lsCount = state.deadlines.filter((d) => d.source === 'learningSuite').length;
    $('ls-status').textContent = lsCount
      ? lsCount + ' item' + (lsCount === 1 ? '' : 's') + ' imported.'
      : 'Nothing imported yet.';

    const canvasCount = state.deadlines.filter((d) => d.source === 'canvas').length;
    $('data-summary').textContent =
      state.deadlines.length + ' cached (' + canvasCount + ' Canvas, ' + lsCount + ' Learning Suite). ' +
      'Stored in this browser only.';
  }

  function render() {
    const now = new Date();

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
      const client = CDT.createClient(settings.canvasHost, settings.canvasToken);
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
      const name = await CDT.createClient(host, token).verifyToken();
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
    if (!confirm('Erase all cached deadlines, your Canvas token, and settings from this browser?')) return;
    state.deadlines = [];
    state.settings = Object.assign({}, store.DEFAULT_SETTINGS);
    save();
    state.banners = [];
    render();
  });

  if (!isExtension && state.settings.canvasToken) {
    banner('error', 'Live sync unavailable here',
      'Canvas refuses direct calls from web pages. Load this folder as a Chrome extension to sync; ' +
      'cached deadlines and Learning Suite import still work.');
  }

  render();
}());
