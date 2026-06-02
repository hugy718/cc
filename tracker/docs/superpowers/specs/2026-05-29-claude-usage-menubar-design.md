# ClaudeUsageBar — Design Spec

**Date:** 2026-05-29
**Status:** Approved, ready for implementation planning

## 1. Purpose

A lightweight native macOS menu bar app that displays Claude Pro/Max subscription
usage at a glance. It shows the two account-level rate-limit windows — the 5-hour
window and the weekly (7-day) window — each as a used-percentage with its absolute
reset time. Clicking the menu bar item opens a small dropdown with progress bars.

The whole point is the always-visible "peek" in the macOS menu bar, so the user can
check remaining headroom without opening anything.

## 2. Scope

### In scope (v1)
- Menu bar item showing both windows (percentage + absolute reset time).
- Dropdown with a minimal progress-bar view of both windows.
- Reading usage data from a local cache file produced by the Claude Code statusline.
- Local display refresh (clock/reset recomputation) every 10 seconds.
- Local detection of a passed reset when no fresh data is available.
- A manual best-effort "Refresh from API" button.
- Minimal settings: launch-at-login, 12h/24h time format, refresh interval.

### Out of scope (v1, explicitly deferred)
- Usage history, charts, or trends.
- Notifications/alerts when approaching a limit.
- Per-session or per-project breakdowns.
- Multi-account support.
- Token-count breakdowns in the dropdown (percentages are enough).

## 3. Data source decision

Claude Code's rate-limit numbers are **request-driven**, not clock-driven: the
percentages (`anthropic-ratelimit-unified-5h-utilization` / `-7d-`) are piggybacked
on the response headers of the actual API messages Claude Code sends, and only change
when tokens are consumed. There is an `/api/oauth/usage` endpoint, but it is
aggressively rate-limited (429s even at 30–60s polling, no `Retry-After`), so it is
**not viable for periodic polling**.

Therefore the data flows through a **local cache file**, not a poller:

- The existing Claude Code statusline script (`~/.claude/statusline-command.sh`)
  already receives `rate_limits` on stdin. We extend it to also write the latest
  values to `~/.claude/usage-cache.json` on every run.
- We add `"refreshInterval": 10` to the statusline config so the script re-runs on a
  timer during active sessions (in addition to its event-driven 300ms-debounced runs).
- The menu bar app reads `usage-cache.json`. It never needs Claude Code running to
  *render*; it only needs the file to *update*.

This is correct rather than a compromise: percentages only change when the user uses
Claude, which is exactly when the file updates. Between sessions, a "stale" percentage
is the true percentage.

## 4. Architecture

Two decoupled cooperating pieces, joined only by the cache file:

### 4.1 Producer — statusline extension (Bash/Python)
- Extends `~/.claude/statusline-command.sh`.
- Continues to emit the normal status line for the terminal.
- Additionally serializes the `rate_limits` block to `~/.claude/usage-cache.json`.
- Writes **atomically**: write to `~/.claude/usage-cache.json.tmp.$$` (PID-suffixed,
  same directory), then `mv` over the target. `rename()` on the same filesystem is
  atomic on macOS, so a reader always sees a complete old or complete new file.

### 4.2 Consumer — menu bar app (Swift / SwiftUI `MenuBarExtra`)
- Native macOS app, ships as a `.app`, launch-at-login capable.
- Reads and decodes `usage-cache.json`.
- Watches the file via FSEvents for instant updates on change.
- Runs a 10-second local timer to recompute the displayed clock/reset times and to
  detect a reset whose `resets_at` has passed.
- Renders the menu bar text and the dropdown.
- Native Keychain access for the manual API-refresh path.

## 5. Concurrency

Multiple concurrent Claude Code sessions may write the cache file. No lock is needed:

1. **Data is account-level**, so all sessions report the same windows — "last write
   wins" is correct, not a conflict.
2. **Torn reads/writes** are prevented by the atomic temp-file + `rename()` in §4.1.
3. **Consumer monotonic guard:** the app tracks the highest `captured_at` it has seen
   and ignores any read whose `captured_at` regressed (an older session renaming
   slightly after a newer one). This keeps "updated Ns ago" from ticking backward.

No `flock`; sessions never block each other.

## 6. Data model

### 6.1 Cache file schema (`~/.claude/usage-cache.json`)
```json
{
  "schema": 1,
  "captured_at": 1780040000,
  "five_hour":  { "used_percentage": 42.0, "resets_at": 1780041720 },
  "seven_day":  { "used_percentage": 18.0, "resets_at": 1780300800 }
}
```
- `schema` — integer version for forward compatibility.
- `captured_at` — epoch seconds when the script wrote the file.
- `*.used_percentage` — float 0–100 (may be absent if the API didn't return it).
- `*.resets_at` — epoch seconds, absolute reset moment (may be absent).

### 6.2 App domain model
- `UsageSnapshot { capturedAt: Date, fiveHour: Window?, sevenDay: Window? }`
- `Window { usedPercentage: Double, resetsAt: Date, isStale: Bool, didReset: Bool }`
  - `isStale` — derived from snapshot age (see §8).
  - `didReset` — `resetsAt` is in the past and no fresher data arrived (see §8).

## 7. Display

### 7.1 Menu bar
Format: both windows, percentage + 24-hour absolute reset time, no text labels,
color-coded. Example:

```
42% →15:42   18% →Sun 16:00
```

- Reset time formatting: same-day → `HH:mm` (`15:42`); other day → `EEE HH:mm`
  (`Sun 16:00`). Honors the 12h/24h setting (§9).
- Color thresholds (reused from existing statusline): green `<50%`, yellow `50–80%`,
  red `>80%`.

### 7.2 Dropdown (minimal layout)
- One row per window: title, percentage (color-coded), a progress bar, and the reset
  time.
- An "updated Ns ago" line derived from `captured_at`.
- A **Refresh** button (§8.3).
- A **Quit** item.
- No token counts.

## 8. Freshness, reset handling, and refresh

### 8.1 "Updated Ns ago"
Computed locally from `captured_at` vs. now, recomputed on the 10s timer.

### 8.2 Stale and reset states
- **Stale:** snapshot older than 30 minutes → numbers shown dimmed.
- **Passed reset:** if a window's `resets_at` is in the past and no fresher snapshot
  has arrived, the app locally shows that window at ~0% with a subtle "awaiting
  refresh" indicator dot — because after a reset with no usage, 0% is the truth.

### 8.3 Manual API refresh
- The **Refresh** button best-effort calls `https://api.anthropic.com/api/oauth/usage`
  using the OAuth token from the Keychain.
- This is the **only** network path and is **manual only** — never polled.
- On HTTP 429, show "rate-limited, try later" and do **not** auto-retry or spin.
- On success, update the in-memory snapshot (and optionally write the cache file via
  the same atomic path so other readers benefit).

## 9. Settings (minimal, `UserDefaults`)
- Launch-at-login toggle.
- 12h / 24h time format.
- Local display refresh interval (default 10s).

## 10. Error handling
- Missing / unparseable cache file → menu bar shows `—`; dropdown text: "No data yet —
  use Claude Code once to populate."
- Malformed JSON on a read → keep last good snapshot, log quietly, do not crash.
- Absent `used_percentage` / `resets_at` fields → render that window as unavailable
  rather than guessing.
- Keychain token unavailable (manual refresh) → button shows "Sign in to Claude Code
  first" state.

## 11. Testing strategy
- **Pure logic in testable structs, no UI/network:**
  - JSON decoding of the cache schema (incl. missing optional fields).
  - Reset-time formatting (same-day vs. other-day; 12h vs. 24h).
  - Color-threshold selection.
  - Stale detection and passed-reset detection given fixture timestamps.
  - Monotonic `captured_at` guard (ignore regressions).
- **Producer:** verify the statusline change by running a real Claude Code turn and
  inspecting the written `usage-cache.json` (correct shape, atomic rename leaves no
  `.tmp` residue).
- Manual API-refresh path tested behind a protocol seam so 429 / success / no-token
  branches are unit-testable with a stubbed client.

## 12. Implementation order

The verification spike comes first so the riskiest assumption is proven before any
Swift is written.

1. **Spike:** extend `statusline-command.sh` to write `usage-cache.json` atomically;
   add `refreshInterval`; run a real Claude Code turn and confirm the file shape.
2. Swift `MenuBarExtra` skeleton that reads the file and renders the menu bar text.
3. File watch (FSEvents) + 10s timer + stale/passed-reset detection + monotonic guard.
4. Dropdown UI (minimal layout).
5. Settings + launch-at-login.
6. Manual "Refresh from API" button (Keychain token, 429-tolerant).

## 13. Open risks
- The `/api/oauth/usage` endpoint shape and auth are undocumented; the manual refresh
  feature may need adjustment or could be dropped if it proves unworkable. The
  statusline file remains the primary, reliable source regardless.
- Keychain item name/format for the OAuth token must be confirmed during step 6.
