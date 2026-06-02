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

  // 1b. Cursor starts on the project header; Enter collapses it (sessions hide),
  //     Enter again re-expands. Guards the two-level tree toggle.
  stdin.write('\r');
  await sleep(80);
  assert.ok(
    !lastFrame().includes('Relax init-workspace perms'),
    'collapsing a project hides its sessions',
  );
  console.log('  PASS collapse hides sessions');
  stdin.write('\r');
  await sleep(80);
  contains(lastFrame(), 'Relax init-workspace perms', 're-expanding shows the sessions again');

  // 2. Move down onto the first session (cursor was on the header), open it.
  stdin.write(DOWN);
  await sleep(50);
  stdin.write('\r');
  await sleep(300);
  const conv = lastFrame();
  contains(conv, 'you', 'conversation shows the user turn');
  contains(conv, 'Edit', 'conversation shows the Edit tool row');
  contains(conv, 'git status', 'conversation shows the Bash command');
  contains(conv, 'Conversation', 'tab bar shows Conversation');

  // EVIDENCE: a frame as tall as the terminal forces a scroll on every repaint
  // (the per-keystroke blink). It must leave at least one free line.
  const maxRows = process.stdout.rows || 24;
  const frameLines = lastFrame().split('\n').length;
  console.log(`  [evidence] frame lines = ${frameLines}, terminal rows = ${maxRows}`);
  assert.ok(
    frameLines <= maxRows - 1,
    `frame fills/overflows the terminal (${frameLines} lines vs ${maxRows} rows) → scroll-flicker`,
  );
  console.log('  PASS frame leaves a free line (no full-height scroll)');

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

  // 6. Drill into the subagent's nested conversation; the drill view must also
  //    leave a free line (same scroll-flicker root cause).
  stdin.write('\r');
  await sleep(250);
  contains(lastFrame(), 'Found it', 'subagent drill shows nested conversation');
  const drillLines = lastFrame().split('\n').length;
  console.log(`  [evidence] drill frame lines = ${drillLines}, terminal rows = ${maxRows}`);
  assert.ok(
    drillLines <= maxRows - 1,
    `drill view fills/overflows the terminal (${drillLines} lines vs ${maxRows} rows) → scroll-flicker`,
  );
  console.log('  PASS drill view leaves a free line');

  console.log('\nSMOKE PASS');
} catch (err) {
  console.error('\nSMOKE FAIL:', err.message);
  unmount();
  process.exit(1);
}
unmount();
process.exit(0);
