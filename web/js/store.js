// Merging and grouping — the rules the iOS app uses, so both keep the same
// data honest in the same way.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.CDT = Object.assign(root.CDT || {}, factory());
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const STORAGE_KEY = 'cougar.deadlines.v1';
  const SETTINGS_KEY = 'cougar.settings.v1';

  // Merges freshly imported items into what is already stored:
  //  - identity is (source, sourceItemId), so a re-sync updates in place
  //  - a hand-set completion always beats the source's value
  //  - items a source stops reporting are dropped only while still upcoming,
  //    so finished coursework does not vanish out of the past
  function merge(existing, imported, source, now) {
    const at = now || new Date();
    const nowIso = at.toISOString();
    const others = existing.filter((d) => d.source !== source);
    const mine = new Map(existing.filter((d) => d.source === source).map((d) => [d.sourceItemId, d]));

    let inserted = 0;
    let updated = 0;
    const kept = [];

    for (const item of imported) {
      const match = mine.get(item.sourceItemId);
      if (match) {
        mine.delete(item.sourceItemId);
        match.courseName = item.courseName;
        match.courseCode = item.courseCode;
        match.title = item.title;
        match.type = item.type;
        match.dueDate = item.dueDate;
        match.url = item.url;
        if (item.details) match.details = item.details;
        if (item.isCompleted != null && !match.completionOverriddenAt) {
          match.isCompleted = item.isCompleted;
        }
        match.lastSyncedAt = nowIso;
        kept.push(match);
        updated += 1;
      } else {
        kept.push(Object.assign({}, item, {
          id: item.source + ':' + item.sourceItemId,
          isCompleted: item.isCompleted === true,
          completionOverriddenAt: null,
          lastSyncedAt: nowIso
        }));
        inserted += 1;
      }
    }

    let removed = 0;
    for (const orphan of mine.values()) {
      if (new Date(orphan.dueDate) >= at) { removed += 1; continue; }
      kept.push(orphan);
    }

    return {
      deadlines: others.concat(kept),
      result: { inserted, updated, removed }
    };
  }

  function setCompleted(deadlines, id, isCompleted, now) {
    return deadlines.map(function (deadline) {
      if (deadline.id !== id) return deadline;
      return Object.assign({}, deadline, {
        isCompleted: isCompleted,
        completionOverriddenAt: (now || new Date()).toISOString()
      });
    });
  }

  function isOverdue(deadline, now) {
    return !deadline.isCompleted && new Date(deadline.dueDate) < (now || new Date());
  }

  function startOfDay(date) {
    const d = new Date(date);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }

  function dayKey(date) {
    const d = startOfDay(date);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }

  function chronologically(a, b) {
    const byDate = new Date(a.dueDate) - new Date(b.dueDate);
    if (byDate) return byDate;
    const labelA = a.courseCode || a.courseName;
    const labelB = b.courseCode || b.courseName;
    if (labelA !== labelB) return labelA < labelB ? -1 : 1;
    return a.title < b.title ? -1 : a.title > b.title ? 1 : 0;
  }

  // Groups by calendar day, days ascending, items within a day by time.
  function byDay(deadlines) {
    const groups = new Map();
    for (const deadline of deadlines) {
      const key = dayKey(deadline.dueDate);
      if (!groups.has(key)) groups.set(key, { key: key, date: startOfDay(deadline.dueDate), deadlines: [] });
      groups.get(key).deadlines.push(deadline);
    }
    return Array.from(groups.values())
      .map((g) => { g.deadlines.sort(chronologically); return g; })
      .sort((a, b) => a.date - b.date);
  }

  // Counts per day — what the calendar badges read, so a badge can never
  // disagree with the list it opens.
  function countsByDay(deadlines, includingCompleted) {
    const counts = new Map();
    for (const deadline of deadlines) {
      if (!includingCompleted && deadline.isCompleted) continue;
      const key = dayKey(deadline.dueDate);
      counts.set(key, (counts.get(key) || 0) + 1);
    }
    return counts;
  }

  const DEFAULT_SETTINGS = {
    canvasHost: 'byu.instructure.com',
    showsCompleted: false,
    learningSuitePath: '/student/assignments'
  };

  // `prefix` namespaces every key, so two people on one browser keep separate
  // deadlines, settings, and Canvas tokens. It partitions; it does not protect —
  // anything in localStorage is readable from the console regardless of who is
  // signed in.
  function createStorage(backing, prefix) {
    const store = backing || (typeof localStorage !== 'undefined' ? localStorage : null);
    const at = prefix || '';
    const deadlinesKey = at + STORAGE_KEY;
    const settingsKey = at + SETTINGS_KEY;

    return {
      prefix: at,
      loadDeadlines() {
        if (!store) return [];
        try { return JSON.parse(store.getItem(deadlinesKey) || '[]'); } catch (_) { return []; }
      },
      saveDeadlines(deadlines) {
        if (!store) return;
        try { store.setItem(deadlinesKey, JSON.stringify(deadlines)); } catch (_) { /* private mode */ }
      },
      loadSettings() {
        if (!store) return Object.assign({}, DEFAULT_SETTINGS);
        try {
          return Object.assign({}, DEFAULT_SETTINGS, JSON.parse(store.getItem(settingsKey) || '{}'));
        } catch (_) { return Object.assign({}, DEFAULT_SETTINGS); }
      },
      saveSettings(settings) {
        if (!store) return;
        try { store.setItem(settingsKey, JSON.stringify(settings)); } catch (_) { /* private mode */ }
      },
      erase() {
        if (!store) return;
        try { store.removeItem(deadlinesKey); store.removeItem(settingsKey); } catch (_) { /* ignore */ }
      }
    };
  }

  return {
    merge, setCompleted, isOverdue, byDay, countsByDay, countsKey: dayKey,
    startOfDay, chronologically, createStorage, DEFAULT_SETTINGS, STORAGE_KEY, SETTINGS_KEY
  };
}));
