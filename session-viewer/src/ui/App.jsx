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
