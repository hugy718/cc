#!/usr/bin/env bash
# init-workspace: apply this project's Claude config to ~/.claude/settings.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_PATH:-$HOME/.claude}"
GLOBAL_SETTINGS="$CLAUDE_DIR/settings.json"

echo "Project root: $PROJECT_ROOT"
echo "Claude config dir: $CLAUDE_DIR"
echo "Global settings: $GLOBAL_SETTINGS"

# --- 1. Copy statusline script ---
SRC_SCRIPT="$PROJECT_ROOT/.claude/statusline-command.sh"
DST_SCRIPT="$CLAUDE_DIR/statusline-command.sh"
if [ -f "$SRC_SCRIPT" ]; then
  cp "$SRC_SCRIPT" "$DST_SCRIPT"
  chmod +x "$DST_SCRIPT"
  echo "Copied statusline-command.sh -> $DST_SCRIPT"
else
  echo "Warning: $SRC_SCRIPT not found, skipping"
fi

# --- 2. Merge settings via Python ---
python3 - <<PYEOF
import json, os, sys

project_root = "$PROJECT_ROOT"
global_path  = "$GLOBAL_SETTINGS"
claude_dir   = "$CLAUDE_DIR"

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

proj   = load(os.path.join(project_root, ".claude", "settings.json"))
local  = load(os.path.join(project_root, ".claude", "settings.local.json"))
global_ = load(global_path)

# --- statusLine: copy from project settings, rewrite path to absolute ---
if "statusLine" in proj:
    sl = dict(proj["statusLine"])
    if "command" in sl:
        sl["command"] = sl["command"].replace(
            "bash .claude/statusline-command.sh",
            f'bash {claude_dir}/statusline-command.sh'
        )
    global_["statusLine"] = sl
    print(f"  statusLine set (command: {sl.get('command', '')})")

# --- permissions: union allow + deny, deduplicated ---
local_perms = local.get("permissions", {})
g_perms = global_.setdefault("permissions", {})

for key in ("allow", "deny"):
    local_entries = local_perms.get(key, [])
    if not local_entries:
        continue
    existing = g_perms.get(key, [])
    merged = list(existing) + [e for e in local_entries if e not in existing]
    g_perms[key] = merged
    added = [e for e in local_entries if e not in existing]
    print(f"  permissions.{key}: {len(added)} new entries added ({len(merged)} total)")

os.makedirs(os.path.dirname(global_path), exist_ok=True)
with open(global_path, "w") as f:
    json.dump(global_, f, indent=2)
    f.write("\n")

print(f"Written: {global_path}")
PYEOF
