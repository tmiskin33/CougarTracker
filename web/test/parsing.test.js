'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const { parseHTML, decodeEntities } = require('../js/html-parse.js');
const { findDate } = require('../js/ls-dates.js');
const { createParser } = require('../js/ls-parse.js');

// The same saved pages the Swift tests use. One set of fixtures keeps the two
// implementations honest against each other.
const FIXTURES = path.join(__dirname, '..', '..', 'CougarDeadlineTrackerTests', 'Fixtures');
const fixture = (name) => fs.readFileSync(path.join(FIXTURES, name), 'utf8');

// A fixed "now" so year inference and overdue checks are deterministic.
const NOW = new Date(2026, 8, 5, 9, 0);
const at = (y, m, d, h = 23, min = 59) => new Date(y, m - 1, d, h, min).toISOString();

test('HTML parser collapses whitespace and decodes entities', () => {
  assert.equal(parseHTML('<p>Hello\n   <b>there</b>  friend</p>').text, 'Hello there friend');
  assert.equal(decodeEntities('1&ndash;25 &amp; &#39;quoted&#x27;'), "1–25 & 'quoted'");
});

test('HTML parser survives unclosed tags', () => {
  const doc = parseHTML('<ul><li>One<li>Two<li>Three</ul>');
  assert.deepEqual(doc.elements('li').map((n) => n.text), ['One', 'Two', 'Three']);
});

test('HTML parser ignores script content and comments', () => {
  const doc = parseHTML("<div>Real<script>var x='<td>fake</td>';</script></div><!-- <p>hidden</p> -->");
  assert.equal(doc.text, 'Real');
  assert.equal(doc.elements('td').length, 0);
  assert.equal(doc.elements('p').length, 0);
});

test('HTML parser reads quoted and unquoted attributes', () => {
  const anchor = parseHTML('<a href="/x/1" class="link primary" data-id=7>Go</a>').firstElement('a');
  assert.equal(anchor.attribute('href'), '/x/1');
  assert.equal(anchor.attribute('data-id'), '7');
  assert.ok(anchor.hasClass('primary'));
});

test('dates: written forms a page actually uses', () => {
  assert.equal(findDate('Sep 8, 2026 11:59 PM', NOW).toISOString(), at(2026, 9, 8));
  assert.equal(findDate('September 8, 2026 at 9:05 AM', NOW).toISOString(), at(2026, 9, 8, 9, 5));
  assert.equal(findDate('Tue, Sep 8 at 11:59 PM', NOW).toISOString(), at(2026, 9, 8));
  assert.equal(findDate('9/12/2026 5:00 PM', NOW).toISOString(), at(2026, 9, 12, 17, 0));
  assert.equal(findDate('9/12/26', NOW).toISOString(), at(2026, 9, 12));
  assert.equal(findDate('Due: Sep 9, 2026 11:59 PM', NOW).toISOString(), at(2026, 9, 9));
});

test('dates: a missing time means end of day', () => {
  assert.equal(findDate('Sep 15', NOW).toISOString(), at(2026, 9, 15));
});

test('dates: a missing year is inferred as the nearest one', () => {
  // Seen in December, "Jan 8" is next year, not ten months ago.
  assert.equal(findDate('Jan 8', new Date(2026, 11, 15)).toISOString(), at(2027, 1, 8));
});

test('dates: midnight and noon convert correctly', () => {
  assert.equal(findDate('Sep 9, 2026 12:00 AM', NOW).toISOString(), at(2026, 9, 9, 0, 0));
  assert.equal(findDate('Sep 9, 2026 12:00 PM', NOW).toISOString(), at(2026, 9, 9, 12, 0));
});

test('dates: text without a date, and impossible dates', () => {
  assert.equal(findDate('Not submitted', NOW), null);
  assert.equal(findDate('', NOW), null);
  assert.equal(findDate('19/45/2026', NOW), null);
});

test('reads a table of assignments', () => {
  const items = createParser().parse(fixture('learningsuite_table.html'), { now: NOW });
  assert.equal(items.length, 3, 'the row with no due date is skipped');
  assert.deepEqual(items.map((i) => i.title), ['Reading Response 3', 'Concert Report', 'Unit 4 Quiz']);
  assert.equal(items[0].courseName, 'A HTG 100');
  assert.equal(items[0].url, 'https://learningsuite.byu.edu/student/assignments/view/44821');
  assert.equal(items[0].dueDate, at(2026, 9, 8));
  assert.equal(items[1].dueDate, at(2026, 9, 12, 17, 0));
  assert.equal(items[2].type, 'quiz');
});

test('"Not submitted" is not read as submitted', () => {
  // Every word meaning "done" is a substring of some phrase meaning the
  // opposite. Getting this backwards hides work still owed.
  const items = createParser().parse(fixture('learningsuite_table.html'), { now: NOW });
  assert.equal(items[0].isCompleted, false);
  assert.equal(items[1].isCompleted, true);
});

test('every spelling of "not done" survives', () => {
  const html = `
    <table>
      <tr><th>Assignment</th><th>Due</th><th>Status</th></tr>
      <tr><td><a href="/a/1">Reading Response</a></td><td>Sep 9, 2026 11:59 PM</td><td>Not submitted</td></tr>
      <tr><td><a href="/a/2">Lab Report</a></td><td>Sep 10, 2026 11:59 PM</td><td>Unsubmitted</td></tr>
      <tr><td><a href="/a/3">Essay Draft</a></td><td>Sep 11, 2026 11:59 PM</td><td>Missing</td></tr>
      <tr><td><a href="/a/4">Final Paper</a></td><td>Sep 12, 2026 11:59 PM</td><td>Submitted</td></tr>
    </table>`;
  const items = createParser().parse(html, { now: NOW });
  assert.deepEqual(items.map((i) => i.isCompleted), [false, false, false, true]);
});

test('falls back to reading cards when there is no table', () => {
  const items = createParser().parse(fixture('learningsuite_cards.html'), { now: NOW });
  assert.deepEqual(items.map((i) => i.title), ['Lab 5 Writeup', 'Rhetorical Analysis Draft', 'Problem Set 6']);
  assert.equal(items[0].courseName, 'PHSCS 121', 'the course comes from the group heading');
  assert.equal(items[1].courseName, 'WRTG 150');
  // Nil, not false: the store must leave a hand-set completion alone.
  assert.ok(items.every((i) => i.isCompleted === null));
});

test('a lapsed session is reported as such, not as a parsing problem', () => {
  assert.throws(
    () => createParser().parse(fixture('learningsuite_login.html'), { now: NOW }),
    (error) => error.kind === 'sessionExpired' && error.requiresReauthentication
  );
});

test('an unreadable page says the site may have changed', () => {
  assert.throws(
    () => createParser().parse(fixture('learningsuite_unrecognised.html'), { now: NOW }),
    (error) => error.kind === 'parsingChanged' && !error.requiresReauthentication
  );
});

test('a page saying nothing is due is not an error', () => {
  const html = '<html><body><div class="assignment-list"><p>No assignments are due.</p></div></body></html>';
  assert.deepEqual(createParser().parse(html, { now: NOW }), []);
});

test('identity is stable across parses and unique within one', () => {
  const parser = createParser();
  const first = parser.parse(fixture('learningsuite_table.html'), { now: NOW });
  const second = parser.parse(fixture('learningsuite_table.html'), { now: NOW });
  assert.deepEqual(first.map((i) => i.sourceItemId), second.map((i) => i.sourceItemId));
  assert.equal(new Set(first.map((i) => i.sourceItemId)).size, first.length);
});

test('selector labels can be retargeted without touching the parser', () => {
  const parser = createParser({ dueColumnLabels: ['fecha'], titleColumnLabels: ['tarea'] });
  const html = `
    <table>
      <tr><th>Tarea</th><th>Fecha</th></tr>
      <tr><td><a href="/x/1">Ensayo</a></td><td>Sep 9, 2026 11:59 PM</td></tr>
    </table>`;
  const items = parser.parse(html, { now: NOW });
  assert.deepEqual(items.map((i) => i.title), ['Ensayo']);
  assert.equal(items[0].dueDate, at(2026, 9, 9));
});
