// test/store.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildIndex, listAllSessions, enrichSummaries, readHead, readSubagentSummaries, defaultRoot } from '../src/io/store.js';
import { toJsonl, subagentRecords } from './fixtures.js';

async function makeRoot() {
  const root = await mkdtemp(path.join(tmpdir(), 'csv-'));
  const proj = path.join(root, '-Users-me-cc');
  await mkdir(proj, { recursive: true });
  await writeFile(path.join(proj, 'sess-1.jsonl'), toJsonl());
  const subdir = path.join(proj, 'sess-1', 'subagents');
  await mkdir(subdir, { recursive: true });
  await writeFile(path.join(subdir, 'agent-aaa111.jsonl'),
    subagentRecords.map((r) => JSON.stringify(r)).join('\n'));
  return { root, proj };
}

test('defaultRoot points at ~/.claude/projects', () => {
  assert.match(defaultRoot(), /\.claude[/\\]projects$/);
});

test('buildIndex lists sessions with summaries', async () => {
  const { root } = await makeRoot();
  const { summaries, unreadable } = await buildIndex(root);
  assert.equal(unreadable, 0);
  assert.equal(summaries.length, 1);
  assert.equal(summaries[0].title, 'Relax init-workspace perms');
  assert.equal(summaries[0].project, '-Users-me-cc');
  assert.equal(summaries[0].id, 'sess-1');
});

test('buildIndex on a missing root returns empty', async () => {
  const { summaries } = await buildIndex('/no/such/dir/xyz');
  assert.deepEqual(summaries, []);
});

test('readHead reads only the first N bytes as whole lines', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'csv-'));
  const p = path.join(root, 'big.jsonl');
  await writeFile(p, 'line-one\nline-two\nline-three\n');
  const lines = await readHead(p, 12); // only "line-one\nlin" fits → partial dropped
  assert.deepEqual(lines, ['line-one']);
});

test('listAllSessions returns stubs (no content read), newest first', async () => {
  const { root } = await makeRoot();
  const stubs = await listAllSessions(root);
  assert.equal(stubs.length, 1);
  assert.equal(stubs[0].id, 'sess-1');
  assert.equal(stubs[0].project, '-Users-me-cc');
  assert.equal(stubs[0].title, '…');           // not yet enriched
  assert.ok(typeof stubs[0].mtime === 'number');
});

test('enrichSummaries fills titles and reports progress in batches', async () => {
  const { root } = await makeRoot();
  const stubs = await listAllSessions(root);
  let batches = 0;
  const out = await enrichSummaries(stubs, { concurrency: 4, batchSize: 1, onBatch: () => { batches++; } });
  assert.equal(out[0].title, 'Relax init-workspace perms');
  assert.equal(out[0].firstPrompt, 'relax the permissions please');
  assert.ok(batches >= 1);
});

test('readSubagentSummaries reads agent files', async () => {
  const { proj } = await makeRoot();
  const subs = await readSubagentSummaries(proj, 'sess-1');
  assert.equal(subs.length, 1);
  assert.equal(subs[0].agentId, 'aaa111');
  assert.equal(subs[0].firstPrompt, 'find the helper');
});
