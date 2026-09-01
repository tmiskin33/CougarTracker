'use strict';
const test = require('node:test');
const assert = require('node:assert');
const store = require('../js/store.js');

const NOW = new Date(2026, 8, 5, 9, 0);

function item(id, dueDate, isCompleted, source) {
  return {
    source: source || 'canvas',
    sourceItemId: id,
    courseName: 'Calculus 2',
    courseCode: 'MATH 113',
    title: 'Homework ' + id,
    type: 'assignment',
    dueDate: new Date(dueDate).toISOString(),
    url: null,
    details: null,
    isCompleted: isCompleted === undefined ? null : isCompleted
  };
}

test('inserts new items', () => {
  const merged = store.merge([], [item('a', '2026-09-20'), item('b', '2026-09-21')], 'canvas', NOW);
  assert.equal(merged.result.inserted, 2);
  assert.equal(merged.deadlines.length, 2);
});

test('a re-sync updates in place rather than duplicating', () => {
  const first = store.merge([], [item('a', '2026-09-20')], 'canvas', NOW);
  const changed = Object.assign(item('a', '2026-09-20'), { title: 'New title' });
  const second = store.merge(first.deadlines, [changed], 'canvas', NOW);

  assert.equal(second.result.inserted, 0);
  assert.equal(second.result.updated, 1);
  assert.equal(second.deadlines.length, 1);
  assert.equal(second.deadlines[0].title, 'New title');
});

test('the same id in two systems is two different items', () => {
  const first = store.merge([], [item('shared', '2026-09-20', null, 'canvas')], 'canvas', NOW);
  const second = store.merge(first.deadlines, [item('shared', '2026-09-20', null, 'learningSuite')], 'learningSuite', NOW);
  assert.equal(second.deadlines.length, 2);
});

test('a hand-set completion survives the next sync', () => {
  const first = store.merge([], [item('a', '2026-09-20', false)], 'canvas', NOW);
  const marked = store.setCompleted(first.deadlines, 'canvas:a', true, NOW);
  const second = store.merge(marked, [item('a', '2026-09-20', false)], 'canvas', NOW);
  assert.equal(second.deadlines[0].isCompleted, true, 'sync must not undo a manual completion');
});

test('a source reporting no completion leaves the local value alone', () => {
  const first = store.merge([], [item('a', '2026-09-20', null, 'learningSuite')], 'learningSuite', NOW);
  const marked = store.setCompleted(first.deadlines, 'learningSuite:a', true, NOW);
  const second = store.merge(marked, [item('a', '2026-09-20', null, 'learningSuite')], 'learningSuite', NOW);
  assert.equal(second.deadlines[0].isCompleted, true);
});

test('upcoming items the source stops reporting are removed', () => {
  const first = store.merge([], [item('a', '2026-09-20'), item('b', '2026-09-21')], 'canvas', NOW);
  const second = store.merge(first.deadlines, [item('a', '2026-09-20')], 'canvas', NOW);
  assert.equal(second.result.removed, 1);
  assert.deepEqual(second.deadlines.map((d) => d.sourceItemId), ['a']);
});

test('past items survive even when the source forgets them', () => {
  const first = store.merge([], [item('old', '2026-08-29')], 'canvas', NOW);
  const second = store.merge(first.deadlines, [], 'canvas', NOW);
  assert.equal(second.result.removed, 0, 'finished coursework must not vanish out of the past');
  assert.equal(second.deadlines.length, 1);
});

test('grouping puts days in order and items within a day by time', () => {
  const deadlines = store.merge([], [
    item('later', '2026-09-08T23:59'),
    item('next', '2026-09-09T09:00'),
    item('earlier', '2026-09-08T09:00')
  ], 'canvas', NOW).deadlines;

  const days = store.byDay(deadlines);
  assert.equal(days.length, 2);
  assert.deepEqual(days[0].deadlines.map((d) => d.sourceItemId), ['earlier', 'later']);
});

test('badge counts match the list they open', () => {
  const deadlines = store.merge([], [
    item('one', '2026-09-08T12:00'),
    item('two', '2026-09-08T18:00'),
    item('done', '2026-09-08T20:00', true)
  ], 'canvas', NOW).deadlines;

  const visible = deadlines.filter((d) => !d.isCompleted);
  const counts = store.countsByDay(visible, false);
  const days = store.byDay(visible);
  const key = store.countsKey(new Date(2026, 8, 8));

  assert.equal(counts.get(key), 2);
  assert.equal(counts.get(key), days[0].deadlines.length);
});

test('overdue means past due and not completed', () => {
  const past = item('p', '2026-09-01T09:00', false);
  const done = Object.assign(item('d', '2026-09-01T09:00'), { isCompleted: true });
  const future = item('f', '2026-09-30T09:00', false);

  assert.equal(store.isOverdue(past, NOW), true);
  assert.equal(store.isOverdue(done, NOW), false);
  assert.equal(store.isOverdue(future, NOW), false);
});
