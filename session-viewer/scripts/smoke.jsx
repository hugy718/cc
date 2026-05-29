// Headless integration smoke for the Ink UI. Renders <App> against a temp
// fixture directory (no real terminal needed) and drives it with simulated
// keystrokes, asserting the rendered frames. Run: `npx tsx scripts/smoke.jsx`.
import React from 'react';
import { render } from 'ink-testing-library';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { App } from '../src/ui/App.jsx';
import { toJsonl, subagentRecords } from '../test/fixtures.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const DOWN = '[B';

async function makeRoot() {
  const root = await mkdtemp(path.join(tmpdir(), 'csv-smoke-'));
  const proj = path.join(root, '-Users-me-cc');
  await mkdir(proj, { recursive: true });
  await writeFile(path.join(proj, 'sess-1.jsonl'), toJsonl());
  const subdir = path.join(proj, 'sess-1', 'subagents');
  await mkdir(subdir, { recursive: true });
  await writeFile(
    path.join(subdir, 'agent-aaa111.jsonl'),
    subagentRecords.map((r) => JSON.stringify(r)).join('\n'),
  );
  return root;
}

function contains(frame, substr, label) {
  assert.ok(
    frame.includes(substr),
    `${label}: expected frame to contain ${JSON.stringify(substr)}\n--- frame ---\n${frame}`,
  );
  console.log(`  PASS ${label}`);
}

const root = await makeRoot();
const { lastFrame, stdin, unmount } = render(<App root={root} />);

try {
  // 1. List renders + title fills in from background enrichment.
  await sleep(300);
  contains(lastFrame(), 'Relax init-workspace perms', 'session title appears in list');
  contains(lastFrame(), '-Users-me-cc', 'project group header appears');

  // 2. Open the session (Enter) -> conversation transcript.
  stdin.write('\r');
  await sleep(300);
  const conv = lastFrame();
  contains(conv, 'you', 'conversation shows the user turn');
  contains(conv, 'Edit', 'conversation shows the Edit tool row');
  contains(conv, 'git status', 'conversation shows the Bash command');
  contains(conv, 'Conversation', 'tab bar shows Conversation');

  // 3. Cursor nav must not crash.
  stdin.write(DOWN);
  await sleep(50);

  // 4. Tab to Tasks view.
  stdin.write('\t');
  await sleep(150);
  contains(lastFrame(), 'Do the thing', 'Tasks view shows the task subject');
  contains(lastFrame(), 'completed', 'Tasks view shows final status');

  // 5. Tab to Subagents view.
  stdin.write('\t');
  await sleep(150);
  contains(lastFrame(), 'Explore', 'Subagents view shows the dispatch');

  console.log('\nSMOKE PASS');
} catch (err) {
  console.error('\nSMOKE FAIL:', err.message);
  unmount();
  process.exit(1);
}
unmount();
process.exit(0);
