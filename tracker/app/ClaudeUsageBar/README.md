# ClaudeUsageBar

A tiny native macOS **menu bar app** that shows your Claude Pro/Max usage at a glance — your **5‑hour** and **weekly** limits, with the percentage used and when each window resets — so you can peek anytime without opening anything.

It lives only in the menu bar (no Dock icon, no window).

---

## What you see

**In the menu bar**, both windows as color‑coded text:

```
42% →15:42   18% →Sun 16:00
```

- The number is **percent used**; the `→time` is when that window **resets** (absolute clock time).
- Color shows urgency: **green** under 50%, **yellow** 50–80%, **red** 80%+.
- Today's resets show as `15:42`; later ones show the weekday, e.g. `Sun 16:00`.

**Click it** for a dropdown with:
- A progress bar, percentage, and reset time for each window.
- "updated Ns ago".
- A **Refresh** button (manual live fetch) and **Quit**.
- Settings: **12‑hour / 24‑hour** clock and **Launch at login**.

---

## Requirements

- macOS 13 or later.
- A Claude **Pro or Max** subscription, signed in through **Claude Code** (the app reads usage that Claude Code already collects).
- To build it: Xcode **Command Line Tools** (`xcode-select --install`). Full Xcode is *not* required.

---

## Install

```bash
# from the repo root
bash tracker/app/make_icon.sh      # builds the app icon (one-time, or after editing icon.svg)
bash tracker/app/package_app.sh    # builds ClaudeUsageBar.app
open tracker/app/ClaudeUsageBar.app
```

You can move `tracker/app/ClaudeUsageBar.app` to `/Applications` if you like.

**One‑time data setup:** the numbers are fed by your Claude Code status line. The repo wires this up by having the status line write your latest usage to `~/.claude/usage-cache.json`. After installing, **use Claude Code once** so that file gets created; the menu bar then shows real numbers. (If you've been using Claude Code already, it's probably there.)

To launch automatically at login, open the dropdown and turn on **Launch at login**.

---

## How it stays up to date

- The menu bar **refreshes its display every 10 seconds** (local only — it recomputes the clock and detects when a window has reset).
- Your actual usage numbers update whenever **Claude Code talks to the API** (which is the only time they change), via the `~/.claude/usage-cache.json` file the app watches.
- **Opening the dropdown also pulls fresh numbers live** from Claude's usage endpoint, then updates in place. To stay friendly with Claude's rate limits, this live pull is throttled to **once every 10 seconds** — reopening sooner just shows the cached numbers.
- Between Claude Code sessions, the shown percentages are still correct (they only change when you actually use Claude). If a window's reset time passes while nothing is running, the app shows it dropped to ~0% with a small "awaiting refresh" dot until fresh data arrives.

---

## Troubleshooting

**A password prompt appears the first time you click Refresh.**
That's macOS asking permission for the app to read your Claude Code login token from the Keychain. Click **Always Allow** and it won't ask again. (The app only reads the token to call Claude's usage endpoint; it's never logged or stored.)

**The dropdown says "Rate‑limited, try later."**
Claude's live usage endpoint limits frequent requests. Wait a bit and reopen — the menu bar still shows your last known numbers in the meantime.

**The menu bar shows `—`.**
No data yet. Use Claude Code once to create `~/.claude/usage-cache.json`, or click Refresh.

**The app icon looks like a blank/old icon in Finder.**
That's the macOS icon cache, not the app. Force a refresh:
```bash
touch /Applications/ClaudeUsageBar.app   # or wherever you put it
killall Finder
```

**Something else is wrong with Refresh.**
The app logs diagnostics to `~/Library/Logs/ClaudeUsageBar.log` (HTTP status and which Keychain field the token came from — never the token itself). Open it to see what happened.

---

## Uninstall

1. Quit the app (menu bar → **Quit**).
2. Delete `ClaudeUsageBar.app`.
3. If you enabled launch‑at‑login, remove `~/Library/LaunchAgents/com.claudeusagebar.agent.plist`.
4. Optional: delete `~/.claude/usage-cache.json` and `~/Library/Logs/ClaudeUsageBar.log`.

---

## For developers

**Layout**
- `tracker/producer/write_usage_cache.py` — invoked by the Claude Code status line; atomically writes account rate‑limits to `~/.claude/usage-cache.json` (temp‑file + rename, so concurrent sessions never corrupt it).
- `tracker/app/ClaudeUsageBar/` — a SwiftPM package:
  - `ClaudeUsageBarCore` — pure, unit‑tested logic: JSON decoding, domain model, reset‑time formatting, color thresholds, stale/passed‑reset evaluation, monotonic `captured_at` guard, menu‑bar text/segments, the OAuth refresh client.
  - `ClaudeUsageBar` — the app shell: AppKit `NSStatusItem` + a SwiftUI popover, a 10s timer, and an FSEvents file watcher.
- `tracker/app/icon.svg`, `make_icon.sh`, `round_corners.swift` — the app icon source and build (rasterizes the SVG and re‑clips to transparent rounded corners, since `qlmanage` flattens onto white).

Built with Command Line Tools only — uses `NSStatusItem` (not SwiftUI `MenuBarExtra`) and a LaunchAgent plist (not `SMAppService`).

**Cache file schema**
```json
{
  "schema": 1,
  "captured_at": 1780040000,
  "five_hour": { "used_percentage": 42.0, "resets_at": 1780041720 },
  "seven_day": { "used_percentage": 18.0, "resets_at": 1780300800 }
}
```
Windows and fields are optional; `0.0` is a valid percentage. (The live `/api/oauth/usage` endpoint uses a different shape — `utilization` plus an ISO‑8601 `resets_at` — which the app converts internally.)

**Tests**
```bash
cd tracker/app/ClaudeUsageBar && swift test          # 34 tests (Swift Testing, CLT-compatible)
python3 -m unittest discover -s tracker/producer/tests -v   # 6 tests (producer)
```

**Edit the icon**
Change `tracker/app/ClaudeUsageBar/Resources/icon.svg`, then `bash tracker/app/make_icon.sh && bash tracker/app/package_app.sh`.
