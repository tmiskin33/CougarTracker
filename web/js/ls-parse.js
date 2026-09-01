// Reads Learning Suite's assignment pages without depending on exact class
// names. Port of LearningSuite/LearningSuiteParsing.swift — same two passes,
// same config, same failure states, so both implementations can be checked
// against the same saved pages.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./html-parse.js'), require('./ls-dates.js'));
  } else {
    root.CDT = Object.assign(root.CDT || {}, factory(root.CDT, root.CDT));
  }
}(typeof self !== 'undefined' ? self : this, function (htmlLib, dateLib) {
  'use strict';

  const parseHTML = htmlLib.parseHTML;
  const findDate = dateLib.findDate;

  const DEFAULT_CONFIG = {
    dueColumnLabels: ['due', 'due date', 'due on', 'date due', 'deadline', 'date'],
    titleColumnLabels: ['assignment', 'title', 'name', 'task', 'item', 'description', 'activity'],
    courseColumnLabels: ['course', 'class', 'section', 'subject'],
    statusColumnLabels: ['status', 'submitted', 'state', 'completed'],
    completedStatusWords: ['submitted', 'complete', 'completed', 'turned in', 'done', 'graded'],
    // Checked before completedStatusWords, because the words that mean "done"
    // appear inside the phrases that mean "not done" — "Not submitted"
    // contains "submitted".
    notCompletedStatusWords: [
      'not submitted', 'unsubmitted', 'not turned in', 'no submission',
      'incomplete', 'not complete', 'not started', 'missing', 'past due', 'late'
    ],
    itemClassHints: ['assignment', 'due', 'task', 'deadline', 'event', 'item', 'row', 'card', 'todo'],
    courseClassHints: ['course', 'class', 'section'],
    loginPageMarkers: ['cas.byu.edu', 'byu net id', 'netid', 'duo security', 'two-factor', 'sign in to byu'],
    ignoredRowWords: ['no assignments', 'nothing due', 'no items']
  };

  // Errors the UI can act on, rather than a bare "it didn't work".
  class ParseFailure extends Error {
    constructor(kind, message) {
      super(message);
      this.name = 'ParseFailure';
      this.kind = kind;                       // 'sessionExpired' | 'parsingChanged'
      this.requiresReauthentication = kind === 'sessionExpired';
    }
  }

  // A hash that stays stable across reloads, so a re-import updates a row
  // rather than duplicating it.
  function stableId(input) {
    let hash = 0xcbf29ce4 >>> 0;
    let low = 0x84222325 >>> 0;
    for (let i = 0; i < input.length; i += 1) {
      const byte = input.charCodeAt(i) & 0xff;
      low ^= byte;
      const a = (hash * 0x01b3) >>> 0;
      const b = (low * 0x01b3) >>> 0;
      hash = (a ^ (b >>> 24)) >>> 0;
      low = b >>> 0;
    }
    return 'ls-' + hash.toString(16) + low.toString(16);
  }

  function matchesLabel(label, candidates) {
    return candidates.some((c) => label === c || label.includes(c));
  }

  function inferType(text) {
    const lowered = String(text).toLowerCase();
    if (/exam|midterm|final/.test(lowered)) return 'exam';
    if (/quiz|test/.test(lowered)) return 'quiz';
    if (/discussion|forum|board/.test(lowered)) return 'discussion';
    if (/assignment|homework|paper/.test(lowered)) return 'assignment';
    return 'other';
  }

  function createParser(overrides) {
    const config = Object.assign({}, DEFAULT_CONFIG, overrides || {});

    function isCompletedStatus(text) {
      const lowered = text.toLowerCase();
      // Negations win outright: otherwise "Not submitted" reads as submitted
      // and ticks off work the student still owes.
      if (config.notCompletedStatusWords.some((w) => lowered.includes(w))) return false;
      return config.completedStatusWords.some((w) => lowered.includes(w));
    }

    function isNoise(title) {
      const lowered = title.toLowerCase();
      if (lowered.length < 2) return true;
      return config.ignoredRowWords.some((w) => lowered.includes(w));
    }

    function looksLikeLoginPage(document) {
      const haystack = document.text.toLowerCase();
      if (config.loginPageMarkers.some((m) => haystack.includes(m.toLowerCase()))) return true;
      return document.elements('input').some((i) => (i.attribute('type') || '').toLowerCase() === 'password');
    }

    function statesNothingIsDue(document) {
      const haystack = document.text.toLowerCase();
      return config.ignoredRowWords.some((w) => haystack.includes(w.toLowerCase()));
    }

    function makeItem(title, course, dueDate, href, isCompleted, context) {
      let url = null;
      if (href) {
        try { url = new URL(href, context.baseUrl).toString(); } catch (_) { url = null; }
      }
      const identity = href || (course + '|' + title + '|' + Math.floor(dueDate.getTime() / 1000));
      return {
        source: 'learningSuite',
        sourceItemId: stableId(identity),
        courseName: course,
        courseCode: '',
        title: title,
        type: inferType(title),
        dueDate: dueDate.toISOString(),
        url: url,
        details: null,
        isCompleted: isCompleted
      };
    }

    function headerColumns(rows) {
      for (const row of rows.slice(0, 3)) {
        const cells = row.childElements().filter((c) => c.tagName === 'th' || c.tagName === 'td');
        if (!cells.length) continue;
        const map = {};
        cells.forEach(function (cell, index) {
          const label = cell.text.toLowerCase().trim();
          if (!label) return;
          if (map.due === undefined && matchesLabel(label, config.dueColumnLabels)) map.due = index;
          if (map.title === undefined && matchesLabel(label, config.titleColumnLabels)) map.title = index;
          if (map.course === undefined && matchesLabel(label, config.courseColumnLabels)) map.course = index;
          if (map.status === undefined && matchesLabel(label, config.statusColumnLabels)) map.status = index;
        });
        if (map.due !== undefined && (map.title !== undefined || map.course !== undefined)) {
          return { row: row, map: map };
        }
      }
      return null;
    }

    // Strategy 1 — tables whose header row names a due-date column.
    function parseTables(document, context) {
      const results = [];
      for (const table of document.elements('table')) {
        const rows = table.elements('tr');
        if (rows.length <= 1) continue;
        const header = headerColumns(rows);
        if (!header) continue;

        for (const row of rows) {
          if (row === header.row) continue;
          const cells = row.childElements().filter((c) => c.tagName === 'td' || c.tagName === 'th');
          if (!cells.length) continue;

          const cellAt = (key) => {
            const index = header.map[key];
            return index === undefined ? null : (cells[index] || null);
          };

          const dueText = cellAt('due') && cellAt('due').text.trim();
          if (!dueText) continue;
          const dueDate = findDate(dueText, context.now);
          if (!dueDate) continue;

          const link = row.elements('a')[0] || null;
          const titleCell = cellAt('title');
          const title = (titleCell && titleCell.text.trim()) || (link && link.text.trim()) || '';
          if (!title || isNoise(title)) continue;

          const courseCell = cellAt('course');
          const course = (courseCell && courseCell.text.trim()) || context.fallbackCourseName;

          const statusCell = cellAt('status');
          const statusText = statusCell && statusCell.text.trim();
          const isCompleted = statusText ? isCompletedStatus(statusText) : null;

          results.push(makeItem(title, course, dueDate, link && link.attribute('href'), isCompleted, context));
        }
      }
      return results;
    }

    // A heading over a group wins over a class name, because a
    // class="course-group" wrapper's own text is the whole group, not its title.
    function courseNameNear(node) {
      let current = node;
      let hops = 0;
      while (current && hops < 6) {
        for (const child of current.children) {
          if (child.kind === 'element' && ['h1', 'h2', 'h3', 'h4'].includes(child.tagName)) {
            const text = child.text.trim();
            if (text && text.length <= 80) return text;
          }
        }
        const names = current.classNames.map((n) => n.toLowerCase());
        if (names.some((name) => config.courseClassHints.some((hint) => name.includes(hint)))) {
          const text = current.text.trim();
          if (text && text.length <= 60) return text;
        }
        current = current.parent;
        hops += 1;
      }
      return null;
    }

    // Strategy 2 — any repeated block holding both a date and a link.
    function parseBlocks(document, context) {
      const candidates = document.elementsWhere(function (node) {
        const tag = node.tagName;
        if (tag === 'li' || tag === 'article') return true;
        if (tag !== 'div' && tag !== 'section' && tag !== 'tr') return false;
        const names = node.classNames.map((n) => n.toLowerCase()).concat([(node.attribute('id') || '').toLowerCase()]);
        return names.some((name) => name && config.itemClassHints.some((hint) => name.includes(hint)));
      });

      // Keep the innermost candidate for each item: an outer wrapper repeats
      // the same date and would double every row.
      const innermost = candidates.filter(function (candidate) {
        return !candidates.some((other) => other !== candidate && other.isDescendantOf(candidate));
      });

      const results = [];
      for (const node of innermost) {
        const text = node.text;
        const dueDate = findDate(text, context.now);
        if (!dueDate) continue;

        const link = node.elements('a')[0] || null;
        let title = (link && link.text.trim()) || '';
        if (!title) {
          for (const tag of ['h1', 'h2', 'h3', 'h4', 'h5', 'strong', 'b']) {
            const heading = node.firstElement(tag);
            if (heading && heading.text.trim()) { title = heading.text.trim(); break; }
          }
        }
        if (!title) title = text.trim();
        if (!title || isNoise(title)) continue;

        const course = courseNameNear(node) || context.fallbackCourseName;
        results.push(makeItem(title.slice(0, 180), course, dueDate, link && link.attribute('href'), null, context));
      }
      return results;
    }

    function parse(html, options) {
      const context = Object.assign({
        now: new Date(),
        fallbackCourseName: 'Learning Suite',
        baseUrl: 'https://learningsuite.byu.edu'
      }, options || {});

      const document = parseHTML(html);
      let results = parseTables(document, context);
      if (!results.length) results = parseBlocks(document, context);

      if (!results.length) {
        if (looksLikeLoginPage(document)) {
          throw new ParseFailure(
            'sessionExpired',
            'That looks like BYU’s sign-in page, not your assignments. Sign in to Learning Suite first, then copy the page again.'
          );
        }
        if (statesNothingIsDue(document)) return [];
        throw new ParseFailure(
          'parsingChanged',
          'The page loaded, but no assignments could be read from it. Learning Suite’s layout may have changed, or there may be nothing due.'
        );
      }

      const seen = new Set();
      return results
        .filter((item) => (seen.has(item.sourceItemId) ? false : seen.add(item.sourceItemId)))
        .sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
    }

    return { parse, config, isCompletedStatus, looksLikeLoginPage };
  }

  return { createParser, DEFAULT_CONFIG, ParseFailure, stableId, inferType };
}));
