// test/render.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toSteps } from '../src/core/normalize.js';
import { buildTaskBoard } from '../src/core/tasks.js';
import { listDispatches } from '../src/core/subagents.js';
import { records } from './fixtures.js';
import {
  shortPath, wrap, sanitize, conversationRows, taskRows, subagentRows,
  diffRows, bashRows, sessionListRows,
} from '../src/ui/render.js';

test('shortPath keeps last two segments', () => {
  assert.equal(shortPath('/a/b/c/d.txt'), 'c/d.txt');
});

test('wrap hard-wraps to width and sanitizes control chars', () => {
  assert.deepEqual(wrap('abcdef', 3), ['abc', 'def']);
  // strips a C0 control char
  assert.equal(sanitize('a\u0001b'), 'ab');
  // MUST preserve spaces, punctuation, tab, and newline (guards against an
  // accidental space-to-hyphen range like /[ --]/ that would eat real text)
  assert.equal(sanitize('a b-c.d'), 'a b-c.d');
  assert.equal(sanitize('a\tb\nc'), 'a\tb\nc');
});

test('conversationRows: head rows carry idx + _head; edit row is drillable', () => {
  const steps = toSteps(records);
  const rows = conversationRows(steps, new Set(), 60);
  const heads = rows.filter((r) => r._head);
  assert.ok(heads.length >= 1);
  const editRow = rows.find((r) => r.style === 'edit');
  assert.match(editRow.text, /Edit/);
  assert.match(editRow.text, /⏎/); // drillable affordance
});

test('taskRows render status icon + trail', () => {
  const rows = taskRows(buildTaskBoard(records), 60);
  assert.ok(rows.some((r) => /Do the thing/.test(r.text)));
  assert.ok(rows.some((r) => /created → in_progress → completed/.test(r.text)));
});

test('subagentRows list dispatches', () => {
  const rows = subagentRows(listDispatches(records), 60);
  assert.ok(rows.some((r) => /Explore/.test(r.text)));
});

test('diffRows mark adds and dels', () => {
  const step = toSteps(records).find((s) => s.subtype === 'edit');
  const rows = diffRows(step, 60);
  assert.ok(rows.some((r) => r.style === 'add'));
  assert.ok(rows.some((r) => r.style === 'del'));
});

test('bashRows include the command and output', () => {
  const step = toSteps(records).find((s) => s.subtype === 'bash');
  const rows = bashRows(step, 60);
  assert.ok(rows.some((r) => /git status/.test(r.text)));
  assert.ok(rows.some((r) => /nothing to commit/.test(r.text)));
});

test('sessionListRows produce group headers and session rows with paths', () => {
  const groups = [{ project: 'p', sessions: [{ title: 'T', path: '/p/s.jsonl' }] }];
  const rows = sessionListRows(groups, new Set(), 40);
  assert.equal(rows[0].style, 'group');
  assert.equal(rows[0].kind, 'project');
  assert.equal(rows[0].project, 'p');
  assert.match(rows[0].text, /▾/); // expanded caret
  assert.equal(rows[1].kind, 'session');
  assert.equal(rows[1].path, '/p/s.jsonl');
});

test('sessionListRows hides sessions of a collapsed project and shows a collapsed caret', () => {
  const groups = [{ project: 'p', sessions: [{ title: 'T', path: '/p/s.jsonl' }] }];
  const rows = sessionListRows(groups, new Set(['p']), 40);
  assert.equal(rows.length, 1);              // header only, no session rows
  assert.equal(rows[0].kind, 'project');
  assert.match(rows[0].text, /▸/);           // collapsed caret
});

// Single source of truth: the row order returned here IS the cursor traversal
// order in the UI, so a project's sessions are always contiguous under its
// header (the bug was that ↑↓ walked a global-mtime array while the screen
// grouped by project — the two orders diverged).
test('sessionListRows keeps each project\'s sessions contiguous under its header, in order', () => {
  const groups = [
    { project: 'p1', sessions: [{ title: 'a', path: '/p1/a' }, { title: 'b', path: '/p1/b' }] },
    { project: 'p2', sessions: [{ title: 'c', path: '/p2/c' }] },
  ];
  const rows = sessionListRows(groups, new Set(), 40);
  assert.deepEqual(
    rows.map((r) => r.kind === 'project' ? `[${r.project}]` : r.path),
    ['[p1]', '/p1/a', '/p1/b', '[p2]', '/p2/c'],
  );
});
