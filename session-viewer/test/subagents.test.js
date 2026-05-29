// test/subagents.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { listDispatches, resolveDispatchFile } from '../src/core/subagents.js';
import { records } from './fixtures.js';

test('listDispatches extracts Agent dispatches with status', () => {
  const ds = listDispatches(records);
  assert.equal(ds.length, 1);
  assert.equal(ds[0].subagentType, 'Explore');
  assert.equal(ds[0].prompt, 'find the helper');
  assert.equal(ds[0].status, 'completed');
});

test('resolveDispatchFile matches by first prompt, consumes used files', () => {
  const summaries = [
    { file: '/a/agent-x.jsonl', agentId: 'x', firstPrompt: 'something else' },
    { file: '/a/agent-y.jsonl', agentId: 'y', firstPrompt: 'find the helper' },
  ];
  const used = new Set();
  const f = resolveDispatchFile({ prompt: 'find the helper' }, summaries, used);
  assert.equal(f, '/a/agent-y.jsonl');
  assert.ok(used.has('/a/agent-y.jsonl'));
  // a second dispatch with the same prompt won't re-pick the consumed file
  assert.equal(resolveDispatchFile({ prompt: 'find the helper' }, summaries, used), null);
});
