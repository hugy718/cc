# ClaudeUsageBar

A native macOS menu bar app that shows Claude Pro/Max usage at a glance: 5-hour and weekly consumption (percentage + absolute reset time), updated every 10 seconds from a local file cache.

## What it shows

- Menu bar title: `5h 42% | 7d 18%` (dashes when data is missing)
- Dropdown popover: progress bars for each window, reset times, "updated Xs ago", **Refresh** (manual API fetch), and **Quit**
- Settings: 12h / 24h clock toggle, launch-at-login toggle

## Architecture — producer / consumer split

```
Claude Code statusline
  └─ runs tracker/producer/write_usage_cache.py
       └─ atomically writes ~/.claude/usage-cache.json
            └─ ClaudeUsageBar.app reads & file-watches that JSON
                 └─ refreshes display every 10 s (local clock / reset recompute)
```

**Producer** (`tracker/producer/write_usage_cache.py`): invoked by the Claude Code statusline hook, reads account rate-limit data from the Claude Code process, and atomically writes it to `~/.claude/usage-cache.json` via a temp-file rename.

**Consumer** (`tracker/app/ClaudeUsageBar`): a SwiftPM package split into:
- `ClaudeUsageBarCore` — pure logic library (unit-tested): schema decoding, domain model, snapshot evaluation (passed-reset zeroing, staleness), menu bar text formatting, settings persistence.
- `ClaudeUsageBar` app shell — wires the core to AppKit (`NSStatusItem`) and a SwiftUI popover; runs a 10-second timer for local refresh; uses `CacheFileWatcher` (FSEvents) for immediate updates.

## Why a file cache, not live API polling

Claude's rate-limit counters only change when you make requests, and the `/api/oauth/usage` endpoint returns HTTP 429 under frequent polling. The statusline-written file is the reliable data source. The app's 10-second refresh is purely local: it recomputes the clock display and detects passed resets (zeroes the percentage). Reset times come from absolute `resets_at` epoch timestamps in the file.

## Cache file schema

```json
{
  "schema": 1,
  "captured_at": 1780040000,
  "five_hour": { "used_percentage": 42.0, "resets_at": 1780041720 },
  "seven_day":  { "used_percentage": 18.0, "resets_at": 1780300800 }
}
```

Both window objects are optional; missing or malformed windows are silently omitted. A `used_percentage` of `0.0` is a valid value (not treated as missing).

## Install / build

### Producer (statusline wiring)

Ensure `~/.claude/statusline-command.sh` invokes the producer script, and that `refreshInterval: 10` is set in the Claude Code statusLine settings. Both are wired as part of the tracker repo setup.

### App

```bash
bash tracker/app/package_app.sh   # produces tracker/app/ClaudeUsageBar.app
open tracker/app/ClaudeUsageBar.app
```

Requires only Command Line Tools (no Xcode). Uses `NSStatusItem` (AppKit, not SwiftUI `MenuBarExtra`) and installs a LaunchAgent plist for launch-at-login.

## Manual Refresh button

The **Refresh** button in the dropdown is a best-effort live fetch: it reads the Claude Code OAuth token from the login Keychain (service `Claude Code-credentials`, keys `accessToken` or `claudeAiOauth.accessToken`), then hits `/api/oauth/usage`. HTTP 429 shows "Rate-limited, try later"; other errors show "Refresh failed". The app never auto-polls this endpoint.

> **Note:** Keychain service name and token JSON shape are best-effort and may need adjustment depending on the Claude Code version installed.

## Tests

```bash
# Swift (CLT-compatible Swift Testing, not XCTest)
cd tracker/app/ClaudeUsageBar && swift test        # expect 31 tests passed

# Python producer
python3 -m unittest discover -s tracker/producer/tests -v   # expect 6 tests passed
```
