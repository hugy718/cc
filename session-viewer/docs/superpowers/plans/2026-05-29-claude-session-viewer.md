# Claude Session Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only interactive terminal app that browses `~/.claude/projects` JSONL sessions — conversation transcript, file edits as diffs, command output, a task board, and subagent drill-ins.

**Architecture:** A pure, unit-tested core (JSONL parsing → normalized steps, diffs, task board, subagent resolution) sits behind a thin `fs` shell and an Ink (React-for-terminal) UI. Core/IO are plain ESM `.js` run directly by `node --test`; UI/CLI are `.jsx` run on the fly by `tsx` (no build step). Heavy content (full diffs, command output, subagent conversations) opens in a drill-in view rather than crowding the transcript.

**Tech Stack:** Node 18+, ESM, Ink 5, React 18, `ink-text-input`, `diff`, `tsx` (dev runner), `node --test` (built-in test runner).

---

## Shared interfaces (used across tasks — keep names consistent)

These are the data shapes every task agrees on. Do not rename fields between tasks.

```text
RawRecord            — a parsed JSON object from one JSONL line (shape varies; fields used:
                       type, message.content, toolUseResult, timestamp, uuid, cwd,
                       gitBranch, sessionId, aiTitle, agentId, isMeta)

ToolResult           — { text: string, structured: any, isError: boolean }

Step (discriminated union, field `kind`):
  { kind:'userPrompt',     text, ts }
  { kind:'assistantText',  text, ts }
  { kind:'thinking',       text, ts }
  { kind:'tool', tool:string, subtype:'edit'|'write'|'bash'|'read'|'agent'|'task'|'other',
                 input:object, id:string, result:ToolResult|null, ts }

DiffResult           — { lines: [{ type:'add'|'del'|'ctx', text }], added:number, removed:number }

Task                 — { id, subject, description, finalStatus, trail: string[] }

Dispatch             — { description, subagentType, prompt, status }

SubagentSummary      — { file:string, agentId:string, firstPrompt:string }

SessionSummary       — { path, sessionId, title, firstPrompt, mtime,
                         cwd, gitBranch, project, projectDir, id, unreadable? }
                       (stub from listAllSessions: title:'…', firstPrompt:'';
                        enriched in the background by a bounded head-read.
                        No messageCount — counting requires a full-file scan.)

Row (for rendering)  — { text:string, style:string, idx?:number, _head?:boolean, path?:string }
                       style ∈ user|ai|plain|dim|edit|bash|add|del|ok|run|meta|accent|group|sess
```

## Efficiency & memory (must hold for large `.claude` folders)

This viewer must stay responsive against many projects and long (multi-MB)
sessions. The design obeys these rules — do not violate them in any task:

1. **Strictly read-only. It never writes any file** — no on-disk cache, no
   generated index, no temp files. All state is in-memory and rebuilt per launch.
2. **The session list is built from bounded head-reads, not full files.** Listing
   uses `readdir`+`stat` only (no content); each title/first-prompt comes from
   reading at most the first ~128 KB of a file (`readHead`). Titles/first prompts
   live at the top of the file, so this is enough; if an `ai-title` line falls
   beyond the head window, the title falls back to the first user prompt.
3. **Startup is instant; titles fill in progressively.** `listAllSessions`
   returns stubs immediately (sorted newest-first); `enrichSummaries` fills titles
   in the background with a concurrency cap, updating the UI in batches.
4. **Opening a session reads exactly one file.** Subagent logs are read **lazily**
   — only when you drill into a specific subagent — and via `readHead` for their
   first prompt. Never eagerly read every subagent file.
5. The only place a whole file is read into memory is the **one** session you open
   (needed to render its transcript), and the rendered row arrays are sliced to
   the viewport by `ScrollView`, so on-screen cost is bounded regardless of length.

File layout:

```text
session-viewer/
  package.json
  src/
    core/   parser.js  normalize.js  diff.js  tasks.js  subagents.js  sessionIndex.js
    io/     store.js
    ui/     theme.js  render.js  scroll.js  ScrollView.jsx  SessionList.jsx
            DrillIn.jsx  useTermSize.jsx  App.jsx
    cli.jsx
  test/   fixtures.js  parser.test.js  normalize.test.js  diff.test.js
          tasks.test.js  subagents.test.js  sessionIndex.test.js  store.test.js
          render.test.js  scroll.test.js
  README.md
```

---

## Phase 0 — Scaffold

### Task 1: Project scaffold

**Files:**
- Create: `package.json`
- Create: `test/smoke.test.js`

- [ ] **Step 1: Create `package.json`**

```json
{
  "name": "claude-session-viewer",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "tsx src/cli.jsx",
    "test": "node --test test/"
  },
  "dependencies": {
    "diff": "^5.2.0",
    "ink": "^5.0.1",
    "ink-text-input": "^6.0.0",
    "react": "^18.3.1"
  },
  "devDependencies": {
    "tsx": "^4.16.0"
  }
}
```

- [ ] **Step 2: Install dependencies**

Run: `cd /Users/bytedance/cc/session-viewer && npm install`
Expected: `node_modules/` created, no errors.

- [ ] **Step 3: Write a smoke test**

```js
// test/smoke.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';

test('test runner works', () => {
  assert.equal(1 + 1, 2);
});
```

- [ ] **Step 4: Run it**

Run: `npm test`
Expected: PASS (1 test passing).

- [ ] **Step 5: Commit**

```bash
git add session-viewer/package.json session-viewer/test/smoke.test.js session-viewer/package-lock.json
git commit -m "chore: scaffold session-viewer node project"
```

---

## Phase 1 — Pure core

### Task 2: JSONL parser + shared fixtures

**Files:**
- Create: `test/fixtures.js`
- Create: `src/core/parser.js`
- Test: `test/parser.test.js`

- [ ] **Step 1: Create shared fixtures** (used by many later tests — do not skip)

```js
// test/fixtures.js
// A realistic mini-session as RawRecord objects.
export const records = [
  { type: 'ai-title', aiTitle: 'Relax init-workspace perms', sessionId: 'sess-1' },
  { type: 'user', timestamp: '2026-05-21T10:00:00Z', cwd: '/Users/me/cc', gitBranch: 'main',
    sessionId: 'sess-1', message: { role: 'user', content: 'relax the permissions please' } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:01Z', message: { role: 'assistant', content: [
      { type: 'thinking', thinking: 'I will edit the settings file.\nTwo lines.' },
      { type: 'text', text: "I'll update the settings file." },
      { type: 'tool_use', id: 'tu-edit', name: 'Edit',
        input: { file_path: '/Users/me/cc/.claude/settings.local.json',
                 old_string: '"deny": []', new_string: '"allow": ["Write"]', replace_all: false } },
  ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:02Z',
    toolUseResult: { filePath: '/Users/me/cc/.claude/settings.local.json' },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-edit', content: 'File updated.' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:03Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-bash', name: 'Bash', input: { command: 'git status' } } ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:04Z',
    toolUseResult: { exitCode: 0, stdout: 'On branch main' },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-bash', content: 'On branch main\nnothing to commit' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:05Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-tc', name: 'TaskCreate',
        input: { subject: 'Do the thing', description: 'details' } } ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:06Z',
    toolUseResult: { task: { id: '1', subject: 'Do the thing' } },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-tc', content: 'created' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:07Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-tu1', name: 'TaskUpdate', input: { taskId: '1', status: 'in_progress' } } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:08Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-tu2', name: 'TaskUpdate', input: { taskId: '1', status: 'completed' } } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:09Z', message: { role: 'assistant', content: [
      { type: 'tool_use', id: 'tu-agent', name: 'Agent',
        input: { description: 'find stuff', subagent_type: 'Explore', prompt: 'find the helper' } } ] } },
  { type: 'user', timestamp: '2026-05-21T10:00:10Z',
    toolUseResult: { status: 'completed' },
    message: { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'tu-agent', content: 'done' } ] } },
  { type: 'assistant', timestamp: '2026-05-21T10:00:11Z',
    message: { role: 'assistant', content: [{ type: 'text', text: 'Done.' }] } },
];

// Same session as raw JSONL text, plus one blank and one malformed line.
export function toJsonl(recs = records) {
  return recs.map((r) => JSON.stringify(r)).join('\n');
}
export const rawJsonl = toJsonl() + '\n\n' + '{ this is not valid json';

// A subagent file's records (its first user message echoes the dispatch prompt).
export const subagentRecords = [
  { type: 'user', isSidechain: true, agentId: 'aaa111', sessionId: 'sess-1',
    message: { role: 'user', content: 'find the helper' } },
  { type: 'assistant', isSidechain: true, agentId: 'aaa111',
    message: { role: 'assistant', content: [{ type: 'text', text: 'Found it.' }] } },
];
```

- [ ] **Step 2: Write the failing test**

```js
// test/parser.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseLine, parseLines } from '../src/core/parser.js';
import { rawJsonl } from './fixtures.js';

test('parseLine: blank -> null, malformed -> undefined, valid -> object', () => {
  assert.equal(parseLine('   '), null);
  assert.equal(parseLine('{bad'), undefined);
  assert.deepEqual(parseLine('{"a":1}'), { a: 1 });
});

test('parseLines: collects records and counts malformed', () => {
  const { records, skipped } = parseLines(rawJsonl);
  assert.equal(skipped, 1);            // the one malformed line
  assert.equal(records[0].type, 'ai-title');
  assert.ok(records.length >= 12);
});
```

- [ ] **Step 2b: Run it to confirm it fails**

Run: `node --test test/parser.test.js`
Expected: FAIL ("Cannot find module '../src/core/parser.js'").

- [ ] **Step 3: Implement `src/core/parser.js`**

```js
// Parse Claude Code session JSONL into raw records.
// null  = blank line (ignore), undefined = malformed (count as skipped).
export function parseLine(line) {
  const t = String(line).trim();
  if (!t) return null;
  try {
    return JSON.parse(t);
  } catch {
    return undefined;
  }
}

export function parseLines(input) {
  const lines = Array.isArray(input) ? input : String(input).split('\n');
  const records = [];
  let skipped = 0;
  for (const line of lines) {
    const r = parseLine(line);
    if (r === null) continue;
    if (r === undefined) { skipped++; continue; }
    records.push(r);
  }
  return { records, skipped };
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/parser.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/core/parser.js session-viewer/test/parser.test.js session-viewer/test/fixtures.js
git commit -m "feat(core): JSONL parser + shared test fixtures"
```

---

### Task 3: Normalize records into steps

**Files:**
- Create: `src/core/normalize.js`
- Test: `test/normalize.test.js`

- [ ] **Step 1: Write the failing test**

```js
// test/normalize.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toSteps, indexToolResults } from '../src/core/normalize.js';
import { records } from './fixtures.js';

test('indexToolResults maps tool_use_id -> result text + structured', () => {
  const map = indexToolResults(records);
  assert.equal(map.get('tu-edit').text, 'File updated.');
  assert.equal(map.get('tu-bash').structured.exitCode, 0);
});

test('toSteps produces ordered, typed steps with paired results', () => {
  const steps = toSteps(records);
  assert.equal(steps[0].kind, 'userPrompt');
  assert.equal(steps[0].text, 'relax the permissions please');
  const thinking = steps.find((s) => s.kind === 'thinking');
  assert.match(thinking.text, /edit the settings/);
  const edit = steps.find((s) => s.kind === 'tool' && s.subtype === 'edit');
  assert.equal(edit.tool, 'Edit');
  assert.equal(edit.result.text, 'File updated.');
  const bash = steps.find((s) => s.kind === 'tool' && s.subtype === 'bash');
  assert.equal(bash.result.structured.exitCode, 0);
  // tool_result-only user records are NOT emitted as userPrompt
  assert.equal(steps.filter((s) => s.kind === 'userPrompt').length, 1);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test test/normalize.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `src/core/normalize.js`**

```js
// Turn raw records into an ordered list of renderable Steps,
// pairing each tool_use with its result.

function blockResultText(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.map((b) => (b.type === 'text' ? b.text : '')).join('\n');
  }
  return '';
}

// Map tool_use_id -> { text, structured, isError }
export function indexToolResults(records) {
  const map = new Map();
  for (const rec of records) {
    const content = rec.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type === 'tool_result') {
        map.set(block.tool_use_id, {
          text: blockResultText(block.content),
          structured: rec.toolUseResult,
          isError: block.is_error === true,
        });
      }
    }
  }
  return map;
}

function subtypeFor(name) {
  switch (name) {
    case 'Edit': return 'edit';
    case 'Write': return 'write';
    case 'Bash': return 'bash';
    case 'Read': case 'Grep': case 'Glob': return 'read';
    case 'Agent': return 'agent';
    case 'TaskCreate': case 'TaskUpdate': case 'TaskList': return 'task';
    default: return 'other';
  }
}

export function toSteps(records) {
  const results = indexToolResults(records);
  const steps = [];
  for (const rec of records) {
    if (rec.type !== 'assistant' && rec.type !== 'user') continue;
    if (rec.isMeta) continue;
    const content = rec.message?.content;
    const ts = rec.timestamp;

    if (typeof content === 'string') {
      if (!content.trim()) continue;
      steps.push({ kind: rec.type === 'user' ? 'userPrompt' : 'assistantText', text: content, ts });
      continue;
    }
    if (!Array.isArray(content)) continue;

    for (const block of content) {
      if (block.type === 'text' && block.text?.trim()) {
        steps.push({ kind: rec.type === 'user' ? 'userPrompt' : 'assistantText', text: block.text, ts });
      } else if (block.type === 'thinking') {
        const text = block.thinking ?? block.text ?? '';
        if (text.trim()) steps.push({ kind: 'thinking', text, ts });
      } else if (block.type === 'tool_use') {
        steps.push({
          kind: 'tool',
          tool: block.name,
          subtype: subtypeFor(block.name),
          input: block.input ?? {},
          id: block.id,
          result: results.get(block.id) ?? null,
          ts,
        });
      }
      // tool_result blocks are intentionally skipped (surfaced via their tool_use step)
    }
  }
  return steps;
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/normalize.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/core/normalize.js session-viewer/test/normalize.test.js
git commit -m "feat(core): normalize records into typed steps with paired results"
```

---

### Task 4: Diff builder

**Files:**
- Create: `src/core/diff.js`
- Test: `test/diff.test.js`

- [ ] **Step 1: Write the failing test**

```js
// test/diff.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lineDiff, editDiff } from '../src/core/diff.js';

test('lineDiff counts added and removed lines', () => {
  const d = lineDiff('a\nb\nc', 'a\nB\nc');
  assert.equal(d.added, 1);
  assert.equal(d.removed, 1);
  assert.ok(d.lines.some((l) => l.type === 'add' && l.text === 'B'));
  assert.ok(d.lines.some((l) => l.type === 'ctx' && l.text === 'a'));
});

test('editDiff: Write is all additions', () => {
  const d = editDiff('Write', { content: 'x\ny' });
  assert.equal(d.removed, 0);
  assert.equal(d.added, 2);
});

test('editDiff: Edit uses old/new strings', () => {
  const d = editDiff('Edit', { old_string: 'foo', new_string: 'bar' });
  assert.equal(d.added, 1);
  assert.equal(d.removed, 1);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test test/diff.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `src/core/diff.js`**

```js
import { diffLines } from 'diff';

export function lineDiff(oldStr, newStr) {
  const parts = diffLines(String(oldStr ?? ''), String(newStr ?? ''));
  const lines = [];
  let added = 0;
  let removed = 0;
  for (const part of parts) {
    const type = part.added ? 'add' : part.removed ? 'del' : 'ctx';
    const segs = part.value.split('\n');
    if (segs.length && segs[segs.length - 1] === '') segs.pop();
    for (const text of segs) {
      lines.push({ type, text });
      if (type === 'add') added++;
      else if (type === 'del') removed++;
    }
  }
  return { lines, added, removed };
}

export function editDiff(toolName, input) {
  if (toolName === 'Write') return lineDiff('', input?.content ?? '');
  return lineDiff(input?.old_string ?? '', input?.new_string ?? '');
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/diff.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/core/diff.js session-viewer/test/diff.test.js
git commit -m "feat(core): line diff builder for edits/writes"
```

---

### Task 5: Task board reconstruction

**Files:**
- Create: `src/core/tasks.js`
- Test: `test/tasks.test.js`

- [ ] **Step 1: Write the failing test**

```js
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
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test test/tasks.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `src/core/tasks.js`**

```js
import { indexToolResults } from './normalize.js';

export function buildTaskBoard(records) {
  const results = indexToolResults(records);
  const tasks = new Map();
  let seq = 0;
  for (const rec of records) {
    if (rec.type !== 'assistant') continue;
    const content = rec.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type !== 'tool_use') continue;
      if (block.name === 'TaskCreate') {
        seq++;
        const id = results.get(block.id)?.structured?.task?.id ?? String(seq);
        tasks.set(id, {
          id,
          subject: block.input?.subject ?? `Task ${id}`,
          description: block.input?.description ?? '',
          finalStatus: 'created',
          trail: ['created'],
        });
      } else if (block.name === 'TaskUpdate') {
        const id = block.input?.taskId;
        const status = block.input?.status;
        if (!id || !status) continue;
        let t = tasks.get(id);
        if (!t) {
          t = { id, subject: `Task ${id}`, description: '', finalStatus: 'created', trail: ['created'] };
          tasks.set(id, t);
        }
        t.trail.push(status);
        t.finalStatus = status;
      }
    }
  }
  return [...tasks.values()];
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/tasks.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/core/tasks.js session-viewer/test/tasks.test.js
git commit -m "feat(core): reconstruct task board from Task* tool calls"
```

---

### Task 6: Subagent dispatches + file resolution

**Files:**
- Create: `src/core/subagents.js`
- Test: `test/subagents.test.js`

- [ ] **Step 1: Write the failing test**

```js
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
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test test/subagents.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `src/core/subagents.js`**

```js
import { indexToolResults } from './normalize.js';

export function listDispatches(records) {
  const results = indexToolResults(records);
  const out = [];
  for (const rec of records) {
    if (rec.type !== 'assistant') continue;
    const content = rec.message?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block.type === 'tool_use' && block.name === 'Agent') {
        out.push({
          description: block.input?.description ?? '',
          subagentType: block.input?.subagent_type ?? 'agent',
          prompt: block.input?.prompt ?? '',
          status: results.get(block.id)?.structured?.status ?? 'unknown',
        });
      }
    }
  }
  return out;
}

// Match a dispatch to its subagent file by first-prompt equality, then by prefix.
// `used` prevents two dispatches from resolving to the same file.
export function resolveDispatchFile(dispatch, summaries, used = new Set()) {
  const norm = (s) => String(s ?? '').trim().slice(0, 200);
  const target = norm(dispatch.prompt);
  if (!target) return null;
  let match = summaries.find((s) => !used.has(s.file) && norm(s.firstPrompt) === target);
  if (!match) {
    const head = target.slice(0, 80);
    match = summaries.find((s) => !used.has(s.file) && norm(s.firstPrompt).startsWith(head));
  }
  if (match) { used.add(match.file); return match.file; }
  return null;
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/subagents.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/core/subagents.js session-viewer/test/subagents.test.js
git commit -m "feat(core): list subagent dispatches and resolve their log files"
```

---

### Task 7: Session summary (index entry)

**Files:**
- Create: `src/core/sessionIndex.js`
- Test: `test/sessionIndex.test.js`

- [ ] **Step 1: Write the failing test**

```js
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
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test test/sessionIndex.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `src/core/sessionIndex.js`**

```js
import { parseLines } from './parser.js';

export function firstUserPrompt(records) {
  for (const rec of records) {
    if (rec.type !== 'user' || rec.isMeta) continue;
    const c = rec.message?.content;
    if (typeof c === 'string' && c.trim()) return c.trim();
    if (Array.isArray(c)) {
      const txt = c.filter((b) => b.type === 'text').map((b) => b.text).join('\n').trim();
      if (txt) return txt;
    }
  }
  return '';
}

// `lines` may be a bounded head-read of the file, not the whole thing —
// title and first prompt live at the top, so that is sufficient.
export function summarize(lines, meta) {
  const { records } = parseLines(lines);
  let title = '';
  let cwd = '';
  let gitBranch = '';
  let sessionId = '';
  for (const rec of records) {
    if (rec.type === 'ai-title' && rec.aiTitle) title = rec.aiTitle;
    if (!cwd && rec.cwd) cwd = rec.cwd;
    if (!gitBranch && rec.gitBranch) gitBranch = rec.gitBranch;
    if (!sessionId && rec.sessionId) sessionId = rec.sessionId;
  }
  const firstPrompt = firstUserPrompt(records);
  if (!title) title = firstPrompt ? firstPrompt.slice(0, 60) : '(untitled)';
  return { path: meta.path, sessionId, title, firstPrompt, mtime: meta.mtime, cwd, gitBranch };
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/sessionIndex.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/core/sessionIndex.js session-viewer/test/sessionIndex.test.js
git commit -m "feat(core): session summary extraction for the index"
```

---

## Phase 2 — IO shell

### Task 8: Filesystem store

**Files:**
- Create: `src/io/store.js`
- Test: `test/store.test.js`

- [ ] **Step 1: Write the failing test** (uses a real temp directory)

```js
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
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test test/store.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `src/io/store.js`**

```js
import { readFile, readdir, stat, open } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { parseLines } from '../core/parser.js';
import { summarize, firstUserPrompt } from '../core/sessionIndex.js';

export function defaultRoot() {
  return path.join(homedir(), '.claude', 'projects');
}

// Read the WHOLE file (only used for the single session the user opens).
export async function readLines(filePath) {
  const text = await readFile(filePath, 'utf8');
  return text.split('\n');
}

// Read at most `maxBytes` from the start and return only the COMPLETE lines.
// Bounds memory/IO per file regardless of session size — used for the index
// and for subagent first-prompts. (Titles/first prompts live at the top.)
export async function readHead(filePath, maxBytes = 131072) {
  const fh = await open(filePath, 'r');
  try {
    const buf = Buffer.alloc(maxBytes);
    const { bytesRead } = await fh.read(buf, 0, maxBytes, 0);
    const text = buf.subarray(0, bytesRead).toString('utf8');
    const lines = text.split('\n');
    if (bytesRead === maxBytes && lines.length > 1) lines.pop(); // drop partial last line
    return lines;
  } finally {
    await fh.close();
  }
}

export async function listProjects(root) {
  let entries;
  try { entries = await readdir(root, { withFileTypes: true }); }
  catch { return []; }
  return entries
    .filter((e) => e.isDirectory())
    .map((e) => ({ name: e.name, dir: path.join(root, e.name) }));
}

export async function listSessions(projectDir) {
  let entries;
  try { entries = await readdir(projectDir, { withFileTypes: true }); }
  catch { return []; }
  const out = [];
  for (const e of entries) {
    if (!e.isFile() || !e.name.endsWith('.jsonl')) continue;
    const p = path.join(projectDir, e.name);
    const s = await stat(p);
    out.push({ id: e.name.replace(/\.jsonl$/, ''), path: p, mtime: s.mtimeMs });
  }
  return out;
}

// Cheap: readdir + stat only, NO file content read. Returns stubs sorted
// newest-first so the UI can render the list instantly.
export async function listAllSessions(root) {
  const projects = await listProjects(root);
  const out = [];
  for (const proj of projects) {
    for (const sess of await listSessions(proj.dir)) {
      out.push({
        ...sess,
        project: proj.name,
        projectDir: proj.dir,
        title: '…',
        firstPrompt: '',
      });
    }
  }
  out.sort((a, b) => b.mtime - a.mtime);
  return out;
}

// Enrich stubs in place (copied) with title/cwd/branch via bounded head-reads,
// running `concurrency` at a time and calling onBatch(snapshot) every batchSize.
export async function enrichSummaries(stubs, { concurrency = 8, batchSize = 24, onBatch } = {}) {
  const result = stubs.map((s) => ({ ...s }));
  let next = 0;
  let done = 0;
  async function worker() {
    while (next < result.length) {
      const i = next++;
      try {
        const head = await readHead(result[i].path);
        const sum = summarize(head, { path: result[i].path, mtime: result[i].mtime });
        result[i] = { ...result[i], ...sum };
      } catch {
        result[i] = { ...result[i], title: result[i].id, unreadable: true };
      }
      done++;
      if (onBatch && done % batchSize === 0) onBatch(result.slice());
    }
  }
  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, worker));
  if (onBatch) onBatch(result.slice());
  return result;
}

// Convenience used by tests / simple callers: list + enrich fully.
export async function buildIndex(root) {
  const stubs = await listAllSessions(root);
  const summaries = await enrichSummaries(stubs, { concurrency: 8 });
  return { summaries, unreadable: summaries.filter((s) => s.unreadable).length };
}

// Read lazily — only when the user drills into a subagent. Bounded head-read.
export async function readSubagentSummaries(projectDir, sessionId) {
  const dir = path.join(projectDir, sessionId, 'subagents');
  let entries;
  try { entries = await readdir(dir, { withFileTypes: true }); }
  catch { return []; }
  const out = [];
  for (const e of entries) {
    if (!e.isFile() || !e.name.startsWith('agent-') || !e.name.endsWith('.jsonl')) continue;
    const p = path.join(dir, e.name);
    const { records } = parseLines(await readHead(p));
    const agentId = records.find((r) => r.agentId)?.agentId
      ?? e.name.slice('agent-'.length).replace(/\.jsonl$/, '');
    out.push({ file: p, agentId, firstPrompt: firstUserPrompt(records) });
  }
  return out;
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/store.test.js`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/io/store.js session-viewer/test/store.test.js
git commit -m "feat(io): filesystem store — index sessions and read subagents"
```

---

## Phase 3 — UI helpers (pure, tested)

### Task 9: Theme + render row-builders

The per-view components from the spec (Conversation / Tasks / Subagents) are implemented as **pure row-builders** here, then rendered generically by `ScrollView` (Task 11). This keeps render logic testable and the components thin.

**Files:**
- Create: `src/ui/theme.js`
- Create: `src/ui/render.js`
- Test: `test/render.test.js`

- [ ] **Step 1: Create `src/ui/theme.js`**

```js
export const ICON = {
  user: '👤', ai: '🤖', thinking: '💭', edit: '✎', bash: '$',
  read: '📄', agent: '⛭', ok: '✔', run: '▶', pending: '○',
};
```

- [ ] **Step 2: Write the failing test**

```js
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
  assert.equal(sanitize('a\u0001b'), 'ab');
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
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `node --test test/render.test.js`
Expected: FAIL (module not found).

- [ ] **Step 4: Implement `src/ui/render.js`**

```js
import { editDiff } from '../core/diff.js';
import { ICON } from './theme.js';

export function sanitize(s) {
  return String(s ?? '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
}

export function wrap(s, width) {
  const w = Math.max(1, width);
  const out = [];
  for (const raw of sanitize(s).split('\n')) {
    if (raw.length <= w) { out.push(raw); continue; }
    let line = raw;
    while (line.length > w) { out.push(line.slice(0, w)); line = line.slice(w); }
    out.push(line);
  }
  return out;
}

export function shortPath(p) {
  if (!p) return '';
  return String(p).split('/').slice(-2).join('/');
}

// One-line headline for a tool step + which drill (if any) it opens.
export function toolHeadline(step) {
  const { subtype, tool, input, result } = step;
  if (subtype === 'edit' || subtype === 'write') {
    const d = editDiff(tool, input);
    return { style: 'edit', text: `${ICON.edit} ${tool}  ${shortPath(input.file_path || '')}  +${d.added} −${d.removed}`, drill: 'diff' };
  }
  if (subtype === 'bash') {
    const cmd = (input.command || '').split('\n')[0];
    const exit = result?.structured?.exitCode;
    const meta = exit !== undefined ? `exit ${exit}` : (result ? 'done' : '');
    return { style: 'bash', text: `${ICON.bash} ${cmd}   ${meta}`, drill: 'bash' };
  }
  if (subtype === 'read') {
    const target = input.file_path || input.path || input.pattern || '';
    return { style: 'dim', text: `${ICON.read} ${tool} ${shortPath(target)}`, drill: result ? 'read' : null };
  }
  if (subtype === 'agent') {
    return { style: 'edit', text: `${ICON.agent} Agent · ${input.subagent_type || ''}`, drill: 'subagent' };
  }
  if (subtype === 'task') {
    const label = tool === 'TaskCreate' ? `+ ${input.subject || ''}`
      : tool === 'TaskUpdate' ? `→ task ${input.taskId} ${input.status}` : 'task list';
    return { style: 'dim', text: `• ${label}`, drill: null };
  }
  return { style: 'dim', text: `· ${tool}`, drill: null };
}

export function conversationRows(steps, expanded, width) {
  const rows = [];
  steps.forEach((step, i) => {
    if (step.kind === 'userPrompt') {
      rows.push({ text: `${ICON.user} you`, style: 'user', idx: i, _head: true });
      for (const l of wrap(step.text, width - 3)) rows.push({ text: '   ' + l, style: 'user', idx: i });
      rows.push({ text: '', style: 'dim', idx: i });
    } else if (step.kind === 'assistantText') {
      rows.push({ text: `${ICON.ai} claude`, style: 'ai', idx: i, _head: true });
      for (const l of wrap(step.text, width - 3)) rows.push({ text: '   ' + l, style: 'plain', idx: i });
      rows.push({ text: '', style: 'dim', idx: i });
    } else if (step.kind === 'thinking') {
      if (expanded.has(i)) {
        rows.push({ text: `${ICON.thinking} thinking`, style: 'dim', idx: i, _head: true });
        for (const l of wrap(step.text, width - 3)) rows.push({ text: '   ' + l, style: 'dim', idx: i });
      } else {
        const n = step.text.split('\n').length;
        rows.push({ text: `${ICON.thinking} thinking · ${n} lines  (⏎ expand)`, style: 'dim', idx: i, _head: true });
      }
      rows.push({ text: '', style: 'dim', idx: i });
    } else if (step.kind === 'tool') {
      const h = toolHeadline(step);
      rows.push({ text: h.drill ? `${h.text}   ⏎` : h.text, style: h.style, idx: i, _head: true });
    }
  });
  if (!rows.length) rows.push({ text: '(empty session)', style: 'dim' });
  return rows;
}

export function taskRows(tasks, width) {
  const rows = [];
  tasks.forEach((t, i) => {
    const icon = t.finalStatus === 'completed' ? ICON.ok : t.finalStatus === 'in_progress' ? ICON.run : ICON.pending;
    const style = t.finalStatus === 'completed' ? 'ok' : t.finalStatus === 'in_progress' ? 'run' : 'dim';
    rows.push({ text: `${icon} ${t.subject}`, style, idx: i, _head: true });
    rows.push({ text: `   ${t.trail.join(' → ')}`, style: 'dim', idx: i });
    if (t.description) for (const l of wrap(t.description, width - 3)) rows.push({ text: '   ' + l, style: 'dim', idx: i });
    rows.push({ text: '', style: 'dim', idx: i });
  });
  if (!rows.length) rows.push({ text: '(no tasks in this session)', style: 'dim' });
  return rows;
}

export function subagentRows(dispatches, width) {
  const rows = [];
  dispatches.forEach((d, i) => {
    rows.push({ text: `${ICON.agent} Agent · ${d.subagentType}   ⏎`, style: 'edit', idx: i, _head: true });
    for (const l of wrap('"' + d.prompt + '"', width - 3).slice(0, 3)) rows.push({ text: '   ' + l, style: 'dim', idx: i });
    rows.push({ text: `   status: ${d.status}`, style: 'dim', idx: i });
    rows.push({ text: '', style: 'dim', idx: i });
  });
  if (!rows.length) rows.push({ text: '(no subagents dispatched)', style: 'dim' });
  return rows;
}

export function diffRows(step, width) {
  const d = editDiff(step.tool, step.input);
  const rows = [{ text: shortPath(step.input?.file_path || ''), style: 'accent' }, { text: '', style: 'dim' }];
  for (const ln of d.lines) {
    const prefix = ln.type === 'add' ? '+ ' : ln.type === 'del' ? '- ' : '  ';
    const style = ln.type === 'add' ? 'add' : ln.type === 'del' ? 'del' : 'plain';
    for (const l of wrap(ln.text, width - 2)) rows.push({ text: prefix + l, style });
  }
  return rows;
}

export function bashRows(step, width) {
  const rows = [];
  for (const l of wrap('$ ' + (step.input?.command ?? ''), width)) rows.push({ text: l, style: 'bash' });
  rows.push({ text: '', style: 'dim' });
  for (const l of wrap(step.result?.text ?? '(no output captured)', width)) rows.push({ text: l, style: 'plain' });
  const exit = step.result?.structured?.exitCode;
  if (exit !== undefined) { rows.push({ text: '', style: 'dim' }); rows.push({ text: `exit ${exit}`, style: 'dim' }); }
  return rows;
}

export function readRows(step, width) {
  return wrap(step.result?.text ?? '(no content)', width).map((l) => ({ text: l, style: 'plain' }));
}

export function sessionListRows(groups, width) {
  const rows = [];
  for (const g of groups) {
    rows.push({ text: `▾ ${g.project}`, style: 'group' });
    for (const s of g.sessions) {
      rows.push({ text: '  ' + String(s.title || '(untitled)').slice(0, Math.max(1, width - 2)), style: 'sess', path: s.path });
    }
  }
  if (!rows.length) rows.push({ text: '(no sessions)', style: 'dim' });
  return rows;
}
```

- [ ] **Step 5: Run tests**

Run: `node --test test/render.test.js`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add session-viewer/src/ui/theme.js session-viewer/src/ui/render.js session-viewer/test/render.test.js
git commit -m "feat(ui): theme + pure row-builders for all views"
```

---

### Task 10: Scroll window logic

**Files:**
- Create: `src/ui/scroll.js`
- Test: `test/scroll.test.js`

- [ ] **Step 1: Write the failing test**

```js
// test/scroll.test.js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clampTop, ensureVisible } from '../src/ui/scroll.js';

test('clampTop keeps top within [0, total-height]', () => {
  assert.equal(clampTop(100, 10, -5), 0);
  assert.equal(clampTop(100, 10, 200), 90);
  assert.equal(clampTop(5, 10, 0), 0); // content shorter than viewport
});

test('ensureVisible scrolls down to reveal the cursor item', () => {
  const rows = [];
  for (let i = 0; i < 50; i++) rows.push({ text: 't', idx: i, _head: true });
  // cursor at idx 40, viewport height 10, currently at top 0 -> should scroll
  const top = ensureVisible(rows, 10, 40, 0);
  assert.ok(top <= 40 && 40 < top + 10);
});

test('ensureVisible scrolls up when cursor above viewport', () => {
  const rows = [];
  for (let i = 0; i < 50; i++) rows.push({ text: 't', idx: i, _head: true });
  const top = ensureVisible(rows, 10, 2, 30);
  assert.equal(top, 2);
});
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `node --test test/scroll.test.js`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `src/ui/scroll.js`**

```js
export function clampTop(totalRows, height, top) {
  const max = Math.max(0, totalRows - height);
  return Math.min(Math.max(0, top), max);
}

// Return a new `top` so the rows belonging to item `cursorIdx` are visible.
export function ensureVisible(rows, height, cursorIdx, top) {
  let first = -1;
  let last = -1;
  rows.forEach((r, i) => {
    if (r.idx === cursorIdx) { if (first < 0) first = i; last = i; }
  });
  if (first < 0) return clampTop(rows.length, height, top);
  let t = top;
  if (first < t) t = first;
  if (last >= t + height) t = last - height + 1;
  return clampTop(rows.length, height, t);
}
```

- [ ] **Step 4: Run tests**

Run: `node --test test/scroll.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/ui/scroll.js session-viewer/test/scroll.test.js
git commit -m "feat(ui): scroll window + cursor-visibility logic"
```

- [ ] **Step 6: Run the whole suite so far**

Run: `npm test`
Expected: all tests PASS (smoke, parser, normalize, diff, tasks, subagents, sessionIndex, store, render, scroll).

---

## Phase 4 — Ink UI

> UI files are `.jsx`, run on the fly by `tsx`. Every `.jsx` file must `import React from 'react'` (the runner uses the classic JSX transform). These components are verified by running the app (manual steps), since their logic lives in the already-tested pure helpers.

### Task 11: ScrollView + terminal-size hook

**Files:**
- Create: `src/ui/useTermSize.jsx`
- Create: `src/ui/ScrollView.jsx`

- [ ] **Step 1: Create `src/ui/useTermSize.jsx`**

```jsx
import { useState, useEffect } from 'react';

export function useTermSize() {
  const read = () => ({ cols: process.stdout.columns || 80, rows: process.stdout.rows || 24 });
  const [size, setSize] = useState(read());
  useEffect(() => {
    const on = () => setSize(read());
    process.stdout.on('resize', on);
    return () => process.stdout.off('resize', on);
  }, []);
  return size;
}
```

- [ ] **Step 2: Create `src/ui/ScrollView.jsx`**

```jsx
import React from 'react';
import { Box, Text } from 'ink';

const STYLE = {
  user: { color: 'yellow' },
  ai: { color: 'green', bold: true },
  plain: {},
  dim: { color: 'gray' },
  edit: { color: 'blue' },
  bash: { color: 'greenBright' },
  add: { color: 'green' },
  del: { color: 'red' },
  ok: { color: 'green' },
  run: { color: 'yellow' },
  meta: { color: 'gray' },
  accent: { color: 'cyan' },
  group: { color: 'blue', bold: true },
  sess: { color: 'gray' },
};

// rows: Row[]; cursorIdx highlights the head row of the cursored item (optional).
export function ScrollView({ rows, height, top, cursorIdx }) {
  const slice = rows.slice(top, top + height);
  return (
    <Box flexDirection="column">
      {slice.map((r, i) => {
        const isCursor = r._head && cursorIdx !== undefined && r.idx === cursorIdx;
        return (
          <Text key={top + i} {...(STYLE[r.style] || {})} inverse={isCursor}>
            {(isCursor ? '▌ ' : '  ') + r.text}
          </Text>
        );
      })}
    </Box>
  );
}
```

- [ ] **Step 3: Commit** (verified once wired into App in Task 14)

```bash
git add session-viewer/src/ui/useTermSize.jsx session-viewer/src/ui/ScrollView.jsx
git commit -m "feat(ui): ScrollView renderer + terminal-size hook"
```

---

### Task 12: SessionList component

**Files:**
- Create: `src/ui/SessionList.jsx`

- [ ] **Step 1: Create `src/ui/SessionList.jsx`**

```jsx
import React from 'react';
import { Box, Text } from 'ink';
import TextInput from 'ink-text-input';
import { sessionListRows } from './render.js';

export function SessionList({ groups, selectedPath, searching, query, onChange, onSubmit, height, width }) {
  const rows = sessionListRows(groups, width);
  let sel = rows.findIndex((r) => r.path && r.path === selectedPath);
  if (sel < 0) sel = 0;
  const listHeight = Math.max(1, height - 1); // first line is the search field
  const top = Math.max(0, Math.min(sel - Math.floor(listHeight / 2), Math.max(0, rows.length - listHeight)));
  const slice = rows.slice(top, top + listHeight);

  return (
    <Box flexDirection="column">
      {searching ? (
        <Box>
          <Text color="cyan">/ </Text>
          <TextInput value={query} onChange={onChange} onSubmit={onSubmit} placeholder="filter…" />
        </Box>
      ) : (
        <Text dimColor>/ {query || 'search'}</Text>
      )}
      {slice.map((r, i) => {
        const selected = r.path && r.path === selectedPath;
        const color = r.style === 'group' ? 'blue' : selected ? 'white' : 'gray';
        return (
          <Text key={top + i} color={color} bold={r.style === 'group'} inverse={!!selected}>
            {r.text}
          </Text>
        );
      })}
    </Box>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add session-viewer/src/ui/SessionList.jsx
git commit -m "feat(ui): session list pane with search field"
```

---

### Task 13: DrillIn component

**Files:**
- Create: `src/ui/DrillIn.jsx`

- [ ] **Step 1: Create `src/ui/DrillIn.jsx`**

```jsx
import React from 'react';
import { Box, Text } from 'ink';
import { ScrollView } from './ScrollView.jsx';

export function DrillIn({ title, rows, top, height }) {
  return (
    <Box flexDirection="column" height={height + 3}>
      <Text color="cyan">▸ {title}</Text>
      <Box flexGrow={1} borderStyle="round" borderColor="blue" paddingX={1}>
        <ScrollView rows={rows} height={height} top={top} />
      </Box>
      <Text dimColor>esc close · ↑↓ scroll · q quit</Text>
    </Box>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add session-viewer/src/ui/DrillIn.jsx
git commit -m "feat(ui): drill-in panel for diffs/output/subagents"
```

---

### Task 14: App orchestration

**Files:**
- Create: `src/ui/App.jsx`

- [ ] **Step 1: Create `src/ui/App.jsx`**

```jsx
import React, { useState, useEffect, useMemo } from 'react';
import { Box, Text, useInput, useApp } from 'ink';
import { useTermSize } from './useTermSize.jsx';
import { ScrollView } from './ScrollView.jsx';
import { SessionList } from './SessionList.jsx';
import { DrillIn } from './DrillIn.jsx';
import * as store from '../io/store.js';
import { parseLines } from '../core/parser.js';
import { toSteps } from '../core/normalize.js';
import { buildTaskBoard } from '../core/tasks.js';
import { listDispatches, resolveDispatchFile } from '../core/subagents.js';
import * as R from './render.js';
import { ensureVisible } from './scroll.js';

function Tabs({ view, session }) {
  const item = (key, label) => (
    <Text key={key} color={view === key ? 'white' : 'gray'} bold={view === key} underline={view === key}>
      {label + '   '}
    </Text>
  );
  return (
    <Box>
      {item('conversation', 'Conversation')}
      {item('tasks', `Tasks·${session.tasks.length}`)}
      {item('subagents', `Subagents·${session.dispatches.length}`)}
    </Box>
  );
}

export function App({ root }) {
  const { exit } = useApp();
  const { cols, rows: termRows } = useTermSize();
  const bodyHeight = Math.max(3, termRows - 2);
  const leftWidth = 30;
  const rightWidth = Math.max(20, cols - leftWidth - 4);

  const [sessions, setSessions] = useState([]); // SessionSummary stubs, enriched in place
  const [scanning, setScanning] = useState(true);
  const [unreadable, setUnreadable] = useState(0);
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [focus, setFocus] = useState('list');
  const [selIdx, setSelIdx] = useState(0);
  const [session, setSession] = useState(null);
  const [view, setView] = useState('conversation');
  const [cursor, setCursor] = useState(0);
  const [expanded, setExpanded] = useState(new Set());
  const [top, setTop] = useState(0);
  const [drill, setDrill] = useState([]);
  const [drillTop, setDrillTop] = useState(0);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setScanning(true);
      const stubs = await store.listAllSessions(root); // cheap: readdir + stat only
      if (cancelled) return;
      setSessions(stubs);                               // render the list instantly
      const enriched = await store.enrichSummaries(stubs, {
        concurrency: 8,
        batchSize: 24,
        onBatch: (snapshot) => { if (!cancelled) setSessions(snapshot); }, // titles fill in progressively
      });
      if (cancelled) return;
      setUnreadable(enriched.filter((s) => s.unreadable).length);
      setScanning(false);
    })();
    return () => { cancelled = true; };
  }, [root]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return sessions;
    return sessions.filter(
      (s) => (s.title || '').toLowerCase().includes(q) || (s.firstPrompt || '').toLowerCase().includes(q),
    );
  }, [sessions, query]);

  useEffect(() => { setSelIdx((i) => Math.max(0, Math.min(i, filtered.length - 1))); }, [filtered.length]);

  const groups = useMemo(() => {
    const m = new Map();
    for (const s of filtered) { if (!m.has(s.project)) m.set(s.project, []); m.get(s.project).push(s); }
    return [...m.entries()].map(([project, sessions]) => ({ project, sessions }));
  }, [filtered]);

  // Opening a session reads exactly ONE file. Subagent logs stay unread
  // (subSummaries: null) until the user drills into a specific subagent.
  async function openSession(summary) {
    const { records } = parseLines(await store.readLines(summary.path));
    setSession({
      summary,
      steps: toSteps(records),
      tasks: buildTaskBoard(records),
      dispatches: listDispatches(records),
      subSummaries: null,
    });
    setView('conversation'); setCursor(0); setTop(0); setExpanded(new Set()); setDrill([]); setFocus('detail');
  }

  const { rows, count } = useMemo(() => {
    if (!session) return { rows: [], count: 0 };
    if (view === 'conversation') return { rows: R.conversationRows(session.steps, expanded, rightWidth), count: session.steps.length };
    if (view === 'tasks') return { rows: R.taskRows(session.tasks, rightWidth), count: session.tasks.length };
    return { rows: R.subagentRows(session.dispatches, rightWidth), count: session.dispatches.length };
  }, [session, view, expanded, rightWidth]);

  useEffect(() => { setTop((t) => ensureVisible(rows, bodyHeight - 1, cursor, t)); }, [cursor, rows, bodyHeight]);

  function pushDrill(d) { setDrill((s) => [...s, d]); setDrillTop(0); }

  async function drillSubagent(dispatch) {
    // Lazily read the subagent directory the first time one is opened, then cache it.
    let subs = session.subSummaries;
    if (subs === null) {
      subs = await store.readSubagentSummaries(session.summary.projectDir, session.summary.id);
      setSession((s) => (s ? { ...s, subSummaries: subs } : s));
    }
    const file = resolveDispatchFile(dispatch, subs, new Set());
    if (!file) { pushDrill({ title: 'subagent', rows: [{ text: '(subagent log not found / ambiguous)', style: 'dim' }] }); return; }
    const { records } = parseLines(await store.readLines(file));
    pushDrill({ title: `⛭ ${dispatch.subagentType}`, rows: R.conversationRows(toSteps(records), new Set(), rightWidth - 2) });
  }

  async function doDrill() {
    if (view === 'conversation') {
      const step = session.steps[cursor];
      if (!step) return;
      if (step.kind === 'thinking') {
        const e = new Set(expanded);
        e.has(cursor) ? e.delete(cursor) : e.add(cursor);
        setExpanded(e);
        return;
      }
      if (step.kind !== 'tool') return;
      if (step.subtype === 'edit' || step.subtype === 'write') {
        pushDrill({ title: `✎ ${R.shortPath(step.input.file_path || '')}`, rows: R.diffRows(step, rightWidth - 2) });
      } else if (step.subtype === 'bash') {
        pushDrill({ title: '$ output', rows: R.bashRows(step, rightWidth - 2) });
      } else if (step.subtype === 'read' && step.result) {
        pushDrill({ title: '📄 result', rows: R.readRows(step, rightWidth - 2) });
      } else if (step.subtype === 'agent') {
        await drillSubagent({ prompt: step.input.prompt || '', subagentType: step.input.subagent_type || '' });
      }
    } else if (view === 'subagents') {
      const d = session.dispatches[cursor];
      if (d) await drillSubagent(d);
    }
  }

  useInput((input, key) => {
    if (searching) return; // TextInput owns input while the search field is open
    if (input === 'q') { exit(); return; }

    if (drill.length) {
      if (key.escape) setDrill((s) => s.slice(0, -1));
      else if (key.upArrow) setDrillTop((t) => Math.max(0, t - 1));
      else if (key.downArrow) setDrillTop((t) => t + 1);
      else if (key.pageUp) setDrillTop((t) => Math.max(0, t - bodyHeight));
      else if (key.pageDown) setDrillTop((t) => t + bodyHeight);
      return;
    }

    if (input === '/') { setSearching(true); return; }
    if (input === 'r') {
      (async () => {
        setScanning(true);
        const stubs = await store.listAllSessions(root);
        setSessions(stubs);
        const enriched = await store.enrichSummaries(stubs, {
          concurrency: 8, batchSize: 24, onBatch: (snap) => setSessions(snap),
        });
        setUnreadable(enriched.filter((s) => s.unreadable).length);
        setScanning(false);
        if (session) openSession(session.summary);
      })();
      return;
    }

    if (focus === 'list') {
      if (key.upArrow) setSelIdx((i) => Math.max(0, i - 1));
      else if (key.downArrow) setSelIdx((i) => Math.min(filtered.length - 1, i + 1));
      else if (key.return || key.rightArrow) { const s = filtered[selIdx]; if (s) openSession(s); }
    } else {
      if (key.upArrow) setCursor((c) => Math.max(0, c - 1));
      else if (key.downArrow) setCursor((c) => Math.min(count - 1, c + 1));
      else if (key.pageUp) setCursor((c) => Math.max(0, c - bodyHeight));
      else if (key.pageDown) setCursor((c) => Math.min(count - 1, c + bodyHeight));
      else if (input === 'g') setCursor(0);
      else if (input === 'G') setCursor(Math.max(0, count - 1));
      else if (key.tab) { setView((v) => (v === 'conversation' ? 'tasks' : v === 'tasks' ? 'subagents' : 'conversation')); setCursor(0); setTop(0); }
      else if (key.return) doDrill();
      else if (key.leftArrow || key.escape) setFocus('list');
    }
  });

  // ---- render ----
  if (drill.length > 0) {
    const d = drill[drill.length - 1];
    return <DrillIn title={d.title} rows={d.rows} top={drillTop} height={termRows - 3} />;
  }

  const hint = focus === 'list'
    ? '↑↓ select · ⏎ open · / search · r refresh · q quit'
    : '↑↓ move · ⏎ drill-in · ⇥ views · ← back · g/G top/bottom · q quit';

  return (
    <Box flexDirection="column" width={cols} height={termRows}>
      <Box height={bodyHeight}>
        <Box width={leftWidth} flexDirection="column" borderStyle="round" borderColor={focus === 'list' ? 'cyan' : 'gray'}>
          <SessionList
            groups={groups}
            selectedPath={filtered[selIdx]?.path}
            searching={searching}
            query={query}
            onChange={setQuery}
            onSubmit={() => setSearching(false)}
            height={bodyHeight - 2}
            width={leftWidth - 2}
          />
        </Box>
        <Box flexGrow={1} flexDirection="column" borderStyle="round" borderColor={focus === 'detail' ? 'cyan' : 'gray'} paddingX={1}>
          {!session ? (
            <Text dimColor>
              {filtered.length} sessions{scanning ? ' · scanning…' : ''}{unreadable ? ` · ${unreadable} unreadable` : ''}. Select one and press ⏎.
            </Text>
          ) : (
            <>
              <Tabs view={view} session={session} />
              <Text dimColor>{session.summary.cwd || ''} · {session.summary.gitBranch || ''}</Text>
              <ScrollView rows={rows} height={bodyHeight - 4} top={top} cursorIdx={focus === 'detail' ? cursor : undefined} />
            </>
          )}
        </Box>
      </Box>
      <Text dimColor>{hint}</Text>
    </Box>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add session-viewer/src/ui/App.jsx
git commit -m "feat(ui): App orchestration — state, keybindings, layout"
```

---

### Task 15: CLI entry + manual verification

**Files:**
- Create: `src/cli.jsx`

- [ ] **Step 1: Create `src/cli.jsx`**

```jsx
import React from 'react';
import { render } from 'ink';
import { App } from './ui/App.jsx';
import * as store from './io/store.js';

const root = process.argv[2] || store.defaultRoot();
render(<App root={root} />);
```

- [ ] **Step 2: Launch against your real sessions**

Run: `cd /Users/bytedance/cc/session-viewer && npm start`
Expected: the two-pane UI renders; the left pane lists projects/sessions from `~/.claude/projects`, newest first.

- [ ] **Step 3: Verify each interaction (check off each)**
  - [ ] The session list appears (near-)instantly with titles filling in as the scan progresses (efficiency: no blocking full-folder read at startup).
  - [ ] `↑/↓` moves the session selection; `⏎` opens a session into the right pane.
  - [ ] Conversation shows your prompts, Claude's replies, collapsed `💭 thinking`, and tool rows.
  - [ ] Move the cursor (`↑/↓` with focus on detail) to an `✎ Edit` row and press `⏎` → a colored diff drill-in opens; `Esc` closes it.
  - [ ] `⏎` on a `$ Bash` row shows command + output; `Esc` closes.
  - [ ] `⏎` on a `💭 thinking` row expands it inline.
  - [ ] `Tab` cycles Conversation → Tasks → Subagents; the Tasks board shows status trails.
  - [ ] On the Subagents tab, `⏎` opens a subagent's nested conversation (use a session with subagents, e.g. one under `-Users-bytedance-cc-tracker`).
  - [ ] `/` opens search; typing filters the list by title/prompt; `Enter` closes the field.
  - [ ] `r` refreshes; `q` quits cleanly (terminal restored).
  - [ ] Resize the terminal — layout adapts without crashing.

- [ ] **Step 4: Fix any issues found, then re-run** `npm start` until all boxes are checked.

- [ ] **Step 5: Commit**

```bash
git add session-viewer/src/cli.jsx
git commit -m "feat(cli): entry point wiring App to ~/.claude/projects"
```

---

## Phase 5 — Polish

### Task 16: README + final verification

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# Claude Session Viewer

An interactive terminal viewer for Claude Code sessions stored under
`~/.claude/projects`. Read-only; writes nothing (no cache/export files). Runs
over SSH on a headless box. Built to stay fast on large `.claude` folders: the
session list comes from a stat-only scan plus bounded head-reads that fill in
titles in the background; a full file is read only for the one session you open,
and subagent logs only when you drill into one.

## Run

```bash
npm install
npm start            # browses ~/.claude/projects
npm start -- /path/to/other/projects
```

## Keys

- `↑/↓` move · `⏎` open session / drill-in · `←`/`Esc` back
- `Tab` switch Conversation / Tasks / Subagents
- `g`/`G` top/bottom · `PgUp`/`PgDn` page
- `/` search (title + your prompts) · `r` refresh · `q` quit

## What it shows

- Conversation transcript (prompts, replies, collapsed thinking)
- File edits as colored diffs, Bash commands with output (drill-in)
- Task board reconstructed from TaskCreate/TaskUpdate
- Subagent dispatches, each drillable into its own nested conversation

## Develop / test

```bash
npm test             # node --test over the pure core + io
```

Core (`src/core`) and IO (`src/io`) are plain ESM and unit-tested. UI
(`src/ui`, `src/cli.jsx`) is Ink/React run via `tsx` (no build step).
````

- [ ] **Step 2: Run the full test suite one more time**

Run: `cd /Users/bytedance/cc/session-viewer && npm test`
Expected: ALL tests pass.

- [ ] **Step 3: Final smoke run**

Run: `npm start`
Expected: app launches and quits cleanly with `q`.

- [ ] **Step 4: Commit**

```bash
git add session-viewer/README.md
git commit -m "docs: README for session viewer"
```

---

## Self-Review (completed during authoring)

**Spec coverage:**
- Node + Ink read-only TUI → Tasks 1, 11–15 ✓
- Browse projects→sessions→conversation → store.listAllSessions + enrichSummaries (8), App/SessionList (12, 14) ✓
- Efficient on large folders → bounded `readHead`, `listAllSessions` (stat-only) + background `enrichSummaries`, lazy subagent reads, no disk writes (8, 14; see "Efficiency & memory") ✓
- Edits as diffs → diff (4), diffRows/render (9), drill-in (13, 14) ✓
- Commands + output → bashRows (9), drill-in (14) ✓
- Task board → tasks (5), taskRows (9), Tasks tab (14) ✓
- Subagents shown separately + nested drill-in → subagents (6), subagentRows (9), drillSubagent (14) ✓
- Search by title+prompts → filtered memo (14), `/` field (12) ✓
- Live refresh → `r` handler (14) ✓
- Progressive disclosure (drill-ins) → DrillIn (13), doDrill (14) ✓
- Edge cases: malformed lines counted (parser 2, store 8 `unreadable`); missing root (8); no ai-title fallback (7); ambiguous subagent (6, 14); terminal resize (11) ✓
- Testing with `node --test` over pure core+io → Tasks 2–10 ✓

**Deviations from spec (intentional, noted):**
1. UI files are `.jsx` run via `tsx` (added dev dep) rather than literal single-file no-build; this keeps `npm start` build-free while allowing clean JSX. Core/IO/tests stay plain `.js` so `node --test` needs no runner.
2. Spec's per-view components (Conversation/TaskBoard/SubagentList) are implemented as pure row-builders in `render.js` rendered by a generic `ScrollView`, instead of three separate components — better separation (logic is pure + unit-tested) and less duplicated rendering code.
3. The drill-in **replaces** the body while open (Esc returns) rather than literally sliding over, because Ink has no overlay/z-index. Behavior is identical from the user's side.
4. The index is built from bounded `readHead` (≤128 KB/file) + stat-only listing with progressive background enrichment, and subagent logs are read lazily on drill-in. `store.readLines` (whole-file) is used only for the single session opened. No `messageCount` (it would force a full-file scan). The app never writes to disk. See the "Efficiency & memory" section.

**Placeholder scan:** none — every code step contains complete, runnable code.

**Type consistency:** `Row` uses `idx`/`_head` uniformly across all row-builders; `ScrollView`/`ensureVisible` key on `r.idx`; `SessionList` keys on `r.path`. `SessionSummary` fields (`path`,`projectDir`,`id`,`title`,`firstPrompt`,`mtime`,`cwd`,`gitBranch`,`project`) are produced by `store.listAllSessions` (stubs) + `enrichSummaries` and consumed consistently in `App`.
```
