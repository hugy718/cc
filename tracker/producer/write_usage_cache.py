#!/usr/bin/env python3
"""Read Claude Code statusline JSON on stdin; write account rate-limit
usage to a cache file via atomic rename. Always exits 0 (never disrupts
the statusline). Output path: $CLAUDE_USAGE_CACHE_PATH or ~/.claude/usage-cache.json."""
import json, os, sys, time, tempfile

def out_path():
    p = os.environ.get("CLAUDE_USAGE_CACHE_PATH")
    if p:
        return p
    return os.path.join(os.path.expanduser("~"), ".claude", "usage-cache.json")

def window(d):
    if not isinstance(d, dict):
        return None
    out = {}
    if d.get("used_percentage") is not None:
        out["used_percentage"] = float(d["used_percentage"])
    if d.get("resets_at") is not None:
        out["resets_at"] = int(d["resets_at"])
    return out or None

def main():
    raw = sys.stdin.read()
    try:
        d = json.loads(raw)
    except Exception:
        return 0
    if not isinstance(d, dict):
        return 0
    rl = d.get("rate_limits")
    if not isinstance(rl, dict):
        return 0
    payload = {"schema": 1, "captured_at": int(time.time())}
    fh = window(rl.get("five_hour"))
    sd = window(rl.get("seven_day"))
    if fh is None and sd is None:
        return 0
    if fh is not None:
        payload["five_hour"] = fh
    if sd is not None:
        payload["seven_day"] = sd
    target = out_path()
    parent = os.path.dirname(os.path.abspath(target))
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".usage-cache.", suffix=".tmp", dir=parent)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(payload, f)
        os.replace(tmp, target)  # atomic on same filesystem
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    return 0

if __name__ == "__main__":
    sys.exit(main())
