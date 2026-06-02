// test/sessionIndex.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summarize, firstUserPrompt } from '../src/core/sessionIndex.js';
import { toJsonl, records } from './fixtures.js';

test('firstUserPrompt returns first real user text, skipping tool_result-only', () => {
  assert.equal(firstUserPrompt(records), 'relax the permissions please');
});

test('summarize extracts title, cwd, branch, counts', () => {
  const lines = toJsonl().split('\n');
  const s = summarize(lines, { path: '/x/sess-1.jsonl', mtime: 123 });
  assert.equal(s.title, 'Relax init-workspace perms');
  assert.equal(s.cwd, '/Users/me/cc');
  assert.equal(s.gitBranch, 'main');
  assert.equal(s.firstPrompt, 'relax the permissions please');
  assert.equal(s.mtime, 123);
});

test('summarize falls back to first prompt when no ai-title', () => {
  const noTitle = records.filter((r) => r.type !== 'ai-title');
  const lines = noTitle.map((r) => JSON.stringify(r));
  const s = summarize(lines, { path: '/x/y.jsonl', mtime: 1 });
  assert.equal(s.title, 'relax the permissions please');
});
