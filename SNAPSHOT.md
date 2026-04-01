# Directory Snapshot

Recorded: 2026-04-02

Generated with:
```
PRUNE_ARGS=$(git ls-files --ignored --exclude-standard --others --directory 2>/dev/null \
  | sed 's|/$||' | awk '{printf "-path ./%s -prune -o ", $0}') && \
eval "find . $PRUNE_ARGS -not -path './.git/*' -ls"
```

## Listing

```
     2646      4 drwxr-xr-x   4 xunf     xunf         4096 Apr  2 00:18 .
   349241      4 -rw-r--r--   1 xunf     xunf         1065 Apr  1 22:49 ./LICENSE
   349242      4 -rw-r--r--   1 xunf     xunf           18 Apr  1 22:49 ./README.md
    14150      4 drwxr-xr-x   9 xunf     xunf         4096 Apr  2 00:14 ./.git
    99948      8 -rw-r--r--   1 xunf     xunf         4733 Apr  2 00:00 ./.gitignore
    97476      4 -rw-r--r--   1 xunf     xunf         1124 Apr  2 00:18 ./SNAPSHOT.md
    97411      4 drwxr-xr-x   3 xunf     xunf         4096 Apr  2 00:20 ./.claude
    97418      4 drwxr-xr-x   3 xunf     xunf         4096 Apr  1 22:53 ./.claude/skills
   136362      4 drwxr-xr-x   2 xunf     xunf         4096 Mar 30 01:37 ./.claude/skills/efficient-fetch
   136363      4 -rw-r--r--   1 xunf     xunf         3691 Mar 30 01:37 ./.claude/skills/efficient-fetch/SKILL.md
```
