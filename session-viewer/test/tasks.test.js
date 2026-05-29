// test/tasks.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildTaskBoard } from '../src/core/tasks.js';
import { records } from './fixtures.js';

test('buildTaskBoard reconstructs id, subject, trail, finalStatus', () => {
  const board = buildTaskBoard(records);
  assert.equal(board.length, 1);
  const t = board[0];
  assert.equal(t.id, '1');
  assert.equal(t.subject, 'Do the thing');
  assert.deepEqual(t.trail, ['created', 'in_progress', 'completed']);
  assert.equal(t.finalStatus, 'completed');
});
