# `.claude` Session Viewer — Design Spec

**Date:** 2026-05-29
**Status:** Approved (design), pending implementation plan
**Location:** `/Users/bytedance/cc/session-viewer`

## 1. Problem

Claude Code stores every session as JSONL under `~/.claude/projects/`. Digging a
past conversation back out of those files is painful: filenames are UUIDs, the
content is one JSON object per line, and the interesting parts (what was edited,
which commands ran, what tasks/subagents were launched) are buried inside nested
message-content arrays. We want a fast way to **browse past sessions and review
the tasks and edits each step made.**

## 2. Form factor

An **interactive terminal UI (TUI)**, written in **Node.js on Ink**, that reads
the JSONL files **live and read-only** and renders a navigable interface. It
writes nothing and runs on a headless server over SSH — the deciding constraint
(a browser File System Access API approach is impossible without a GUI browser,
and a static Markdown/HTML export is not interactive, which the user explicitly
wants).

Run as: `node src/cli.js [rootPath]` — `rootPath` defaults to
`~/.claude/projects`.

## 3. Goals / Non-goals

**Goals**
- Browse all projects → sessions → a single conversation, fast.
- Read the conversation as a clean transcript (your prompts + Claude's replies).
- See **file edits as diffs**, **commands + their output**, with progressive
  disclosure (drill-ins), never cramming standalone content onto one screen.
- See the **task tracker** (TaskCreate/TaskUpdate) as a status board.
- See **subagent dispatches** separately, each drillable into its own nested
  conversation.
- Filter/search the session list by **title + your prompts**.
- Live: re-scan on demand to pick up new sessions.

**Non-goals (YAGNI)**
- Read-only. No editing or writing back to any file.
- No static export (that was a rejected alternative).
- No full-text search across message bodies in v1 (index is title + prompts).
- No syntax highlighting in v1 beyond diff add/remove coloring.
- Keyboard-first; no mouse support required.
- Single root only (`~/.claude/projects`).

## 4. Input data model (as observed)

- **Project dir:** `~/.claude/projects/<sanitized-cwd>/` where `<sanitized-cwd>`
  is the absolute cwd with `/` → `-` (e.g. `/Users/bytedance/cc` →
  `-Users-bytedance-cc`). The real cwd is available verbatim in each record's
  `cwd` field — prefer that for display over de-sanitizing the dir name.
- **Session file:** `<session-uuid>.jsonl`, one JSON object per line.
- **Subagent files:** `<session-uuid>/subagents/agent-<agentId>.jsonl`; their
  records carry `isSidechain: true` and an `agentId`.

**Line `type` values seen:** `user`, `assistant`, `system`, `attachment`,
`permission-mode`, `file-history-snapshot`, `ai-title`, `last-prompt`.
Unrecognized types must be skipped gracefully.

**Common top-level keys:** `parentUuid`, `isSidechain`, `type`, `message`,
`uuid`, `timestamp`, `cwd`, `sessionId`, `version`, `gitBranch`,
`toolUseResult`, `durationMs`, `requestId`, `isMeta`.

**`message.content`** is either a **string** or an **array of blocks**:
- `text` → assistant/user prose
- `thinking` → reasoning (collapsed by default)
- `tool_use` → `{ id, name, input }`
- `tool_result` → `{ tool_use_id, content }`

**Tool input shapes (confirmed):**
- `Edit`: `{ file_path, old_string, new_string, replace_all }`
- `Write`: `{ file_path, content }`
- `Bash`: `{ command, ... }`
- `Agent`: `{ description, subagent_type, prompt }`
- `TaskCreate`: `{ subject, description }`
- `TaskUpdate`: `{ taskId, status }`
- `TaskList`: `{}`

**Result pairing:** a `tool_use` block is matched to its result by
`tool_use_id`, found in a later `tool_result` block; richer structured output is
on the sibling top-level `toolUseResult` field of the same record. Use both.

**Title:** `{ type: "ai-title", aiTitle, sessionId }` — may repeat; take the last
non-empty. Fall back to the first user prompt if absent.

**Tasks:** `TaskCreate`'s `toolUseResult` is `{ task: { id, subject } }`; ids are
sequential strings ("1", "2", …) in creation order. `TaskUpdate { taskId, status }`
applies transitions. Reconstruct each task's final status + ordered status trail.

**Subagent linkage:** the `Agent` dispatch's `toolUseResult` does not carry the
`agentId`. Join a dispatch to its `agent-<agentId>.jsonl` file by matching the
file's **first user prompt** to the dispatch `input.prompt` (disambiguate ties by
`description`, then by file creation order). Load the file only on drill-in.

## 5. Architecture

Three layers, with a hard boundary so the logic is testable without a terminal:

### Pure core — no I/O, no DOM/Ink (unit-tested with `node --test`)
- `src/core/parser.js` — one JSONL line → typed record; tolerates malformed
  lines (skip + count); normalizes `content` string-or-array.
- `src/core/normalize.js` — records → an ordered list of **Steps**:
  `userPrompt | assistantText | thinking | toolCall | toolResult`, where
  `toolCall` is subtyped `edit | write | bash | read | agent | task | other`;
  pairs each `tool_use` with its result by id.
- `src/core/sessionIndex.js` — build a `SessionSummary` per file: title, first prompt,
  message count, mtime, cwd, gitBranch, path. **Streaming scan**: read the file
  line by line, retain only summary fields, discard the rest (so multi-MB files
  index cheaply).
- `src/core/diff.js` — `old_string`→`new_string` line diff (Write → full new
  content). Uses the `diff` npm package.
- `src/core/tasks.js` — replay Task* calls into a board: `[{ id, subject,
  description, finalStatus, trail: [status…] }]`.
- `src/core/subagents.js` — list a session's `Agent` dispatches and resolve each
  to its subagent file path via the prompt-match join.

### I/O shell (thin, browser-of-filesystem)
- `src/io/store.js` — locate the root; list project dirs and session files;
  stream a file's lines; `fs.stat` for mtime; resolve subagent files; decode the
  real cwd. The only module that touches `fs`.

### UI (Ink components)
- `src/ui/App.jsx` — owns state: focused pane, selected project/session, active
  right-pane view (Conversation | Tasks | Subagents), step cursor, drill-in
  stack, search query.
- `src/ui/SessionList.jsx` — left pane: sessions grouped by project, newest
  first, title + preview; `/` filters over title + prompts.
- `src/ui/Conversation.jsx` — right pane: scrollable transcript; compact tool
  rows; `thinking` collapsed (toggle to expand inline). Reused recursively to
  render a subagent's conversation in a drill-in.
- `src/ui/DrillIn.jsx` — overlay panel: full diff, full command output, or a
  subagent conversation. Stackable; Esc pops.
- `src/ui/TaskBoard.jsx` — Tasks view.
- `src/ui/SubagentList.jsx` — Subagents view; Enter opens the nested conversation.
- `src/ui/ScrollView.jsx` — hand-rolled scroll viewport (Ink ships none): tracks
  an offset, slices visible lines to terminal height, handles ↑↓ / PgUp/PgDn /
  g/G. This is the main piece of custom UI work.
- `src/ui/render.js` — shared helpers: tool-row formatting, minimal
  terminal-markdown (preserve/colorize fenced code, bold), width wrapping, and
  control-character sanitizing so file content can't corrupt the terminal.

### Data flow
`store.listProjects/listSessions → core/index (streaming) → SessionList`. On
select: `store.readLines → parser → normalize → Conversation + TaskBoard +
SubagentList`. Drill-in renders diff/output/subagent on demand. `r` re-scans.

## 6. UX

### Layout (approved)
Two panes, always visible: session list (left, ~28 cols), detail (right). The
right pane has three tabbed views — **Conversation / Tasks / Subagents** — plus a
slide-over **drill-in** panel for heavy content. A bottom hint bar shows
keybindings. VSCode-dark palette.

### Views
1. **Conversation** — chronological steps: `👤 you`, collapsed `💭 thinking`,
   `🤖 claude` text, and compact tool rows:
   - `✎ Edit  <file>  +A −D  ⏎` → drill-in: colored line diff.
   - `$ Bash  <cmd>  exit N  ⏎` → drill-in: command + stdout/stderr + exit.
   - `📄 Read <file>` → optional drill-in to the read result.
   - `⛭ Agent · <type>  ⏎` → drill-in: subagent conversation.
   - Task* calls render as compact rows; the board lives in the Tasks view.
2. **Tasks** — each task with status icon (`✔` completed / `▶` in_progress / `○`
   pending), subject, and its `created → … ` transition trail.
3. **Subagents** — one card per `Agent` dispatch (subagent_type, prompt preview,
   step count); Enter opens its conversation as a nested drill-in.

### Keybindings
- Global: `q` quit · `?` help · `r` refresh (re-scan) · `/` search session list.
- Session list focus: `↑/↓` select · `Enter` or `→` open session (focus → right).
- Detail focus: `↑/↓` move step cursor / scroll · `Enter` drill-in on the
  cursored step · `Tab` cycle Conversation→Tasks→Subagents · `←`/`Esc` back to
  list · `g`/`G` top/bottom · `PgUp`/`PgDn` page.
- Drill-in: `↑/↓` scroll · `Esc` close (pops one level of the stack).

## 7. Edge cases & error handling

- No root dir / empty root → friendly empty state with the resolved path.
- Malformed JSON lines → skipped and counted; surface "N unreadable lines" subtly.
- `content` as string vs array → both handled in `parser`.
- Large files (seen up to ~1.9 MB) → streamed for indexing; full parse only on
  open; long outputs/diffs scroll within the drill-in.
- Missing `ai-title` → first-prompt fallback.
- Missing/duplicate subagent file or ambiguous prompt-match → show the dispatch
  card with a "subagent log not found / ambiguous" note instead of failing.
- Sanitized dir name → display real `cwd` from a record.
- Terminal too small → minimum-size message until resized.
- Long lines → wrapped to width; never crash layout.

## 8. Testing

- `node --test` (built-in, no dependency) over the pure core:
  `parser`, `normalize`, `sessionIndex`, `diff`, `tasks`, `subagents`.
- Fixtures under `test/fixtures/`: a normal session, a malformed-line session, a
  session with edits + bash + reads, a task-heavy session, and a session with a
  subagent (plus its `subagents/agent-*.jsonl`).
- Pin behavior on: result pairing by `tool_use_id`, task trail reconstruction,
  diff line counts, and the subagent prompt-match join.
- UI (`App`, components, `store`) verified manually in-terminal; optional
  `ink-testing-library` dev-dep for component smoke tests.

## 9. Dependencies

Runtime: `ink`, `react` (Ink peer), `ink-text-input` (search), `diff`.
Dev: `node --test` (built-in); optional `ink-testing-library`.
Keep the tree minimal; no blessed (Ink chosen for the maintained,
component-model API — the only cost is the hand-rolled `ScrollView`).

## 10. Risks

- **Scroll viewport**: hand-rolling scrolling/virtualization in Ink for long
  conversations is the highest-effort piece; budget for it explicitly.
- **Subagent join**: prompt-matching is reliable but not guaranteed unique; the
  ambiguous-match fallback (§7) keeps it from breaking the view.
- **Markdown in a terminal**: kept intentionally minimal in v1; revisit if
  prose readability suffers.

## 11. Out of scope / future

Static Markdown/HTML export; full-text search; syntax highlighting; mouse
support; multiple roots; following `parentUuid` to render non-linear branches
(v1 renders chronological file order, which is correct for linear sessions).
