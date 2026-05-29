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
  assert.equal(sanitize('ab'), 'ab');
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
  const rows = sessionListRows(groups, 40);
  assert.equal(rows[0].style, 'group');
  assert.equal(rows[1].path, '/p/s.jsonl');
});
