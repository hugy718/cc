---
name: dir-snapshot
description: >
  Record a snapshot of the current directory's file tree and timestamps into SNAPSHOT.md,
  or check whether the directory has changed since the last SNAPSHOT.md was recorded.
  Trigger this skill when the user asks to: "snapshot this directory", "record the current
  state", "check for changes since last snapshot", "has anything changed since the snapshot",
  "update the snapshot", or "diff against snapshot". Also trigger when the user mentions
  SNAPSHOT.md directly.
---

# dir-snapshot

Two operations: **record** a snapshot, or **check** for changes against an existing one.

## Shared: building the file listing

Use this command from the project root (or target directory) to get a listing that respects `.gitignore`:

```bash
PRUNE_ARGS=$(git ls-files --ignored --exclude-standard --others --directory 2>/dev/null \
  | sed 's|/$||' | awk '{printf "-path ./%s -prune -o ", $0}') && \
eval "find . $PRUNE_ARGS -not -path './.git/*' -ls"
```

If there is no `.git` directory, fall back to plain `find . -ls` and skip the gitignore pruning step.

The `-ls` output format is:
```
<inode> <blocks> <perms> <links> <user> <group> <size> <month> <day> <time/year> <path>
```

The key fields for detecting change are **size**, **timestamp** (columns 7–10), and **path** (last column).

## Operation 1: Record a snapshot

Write a `SNAPSHOT.md` in the current directory with:
1. The date recorded
2. The command used to generate the listing
3. The raw output of the listing inside a code block

Template:
```markdown
# Directory Snapshot

Recorded: <YYYY-MM-DD>

Generated with:
\```
PRUNE_ARGS=$(git ls-files --ignored --exclude-standard --others --directory 2>/dev/null \
  | sed 's|/$||' | awk '{printf "-path ./%s -prune -o ", $0}') && \
eval "find . $PRUNE_ARGS -not -path './.git/*' -ls"
\```

## Listing

\```
<output here>
\```
```

After writing, confirm to the user: "Snapshot recorded to SNAPSHOT.md — <N> entries."

## Operation 2: Check for changes

Use shell tools to compute the diff — do not load both listings into context and compare manually, as that wastes tokens.

```bash
# 1. Extract the saved listing from SNAPSHOT.md into a temp file
#    (strips the markdown fences, keeps only the listing block)
sed -n '/^## Listing$/,/^```$/{ /^```/d; /^## Listing$/d; p }' SNAPSHOT.md > /tmp/snapshot_old.txt

# 2. Generate current listing into another temp file
PRUNE_ARGS=$(git ls-files --ignored --exclude-standard --others --directory 2>/dev/null \
  | sed 's|/$||' | awk '{printf "-path ./%s -prune -o ", $0}')
eval "find . $PRUNE_ARGS -not -path './.git/*' -ls" > /tmp/snapshot_new.txt

# 3. Normalise: strip inode+blocks (cols 1-2) and compare on perms+owner+size+time+path
awk '{$1=$2=""; print}' /tmp/snapshot_old.txt | sort > /tmp/snap_old_norm.txt
awk '{$1=$2=""; print}' /tmp/snapshot_new.txt | sort > /tmp/snap_new_norm.txt

# 4. Diff — only changed lines reach context
diff /tmp/snap_old_norm.txt /tmp/snap_new_norm.txt
```

Read only the `diff` output. Interpret it:
- Lines starting with `<` are from the snapshot (old)
- Lines starting with `>` are current (new)
- A path appearing only in `<` = **REMOVED**
- A path appearing only in `>` = **NEW**
- A path in both `<` and `>` with different fields = **MODIFIED** (show what changed)

Present a summary table:

```
Status      Path
──────────  ─────────────────────────────
NEW         ./src/new_file.py
MODIFIED    ./.claude/settings.local.json   (size: 497 → 612, Apr 1 23:54 → Apr 2 10:01)
REMOVED     ./old_config.json
```

If `diff` produces no output: "No changes detected since snapshot recorded on <date>."

Offer to update the snapshot after showing the diff.
