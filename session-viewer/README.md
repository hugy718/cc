# Claude Session Viewer

An interactive terminal viewer for Claude Code sessions stored under
`~/.claude/projects`. Read-only; writes nothing (no cache/export files). Runs
over SSH on a headless box.

Built to stay fast on large `.claude` folders: the session list comes from a
stat-only scan plus bounded head-reads that fill in titles in the background; a
full file is read only for the one session you open, and subagent logs only when
you drill into one.

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
npm run smoke        # headless Ink render smoke (ink-testing-library)
```

Core (`src/core`) and IO (`src/io`) are plain ESM and unit-tested. UI
(`src/ui`, `src/cli.jsx`) is Ink/React run via `tsx` (no build step).
