# ClaudeUsageBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that displays Claude Pro/Max 5-hour and weekly usage (percentage + absolute reset time), fed by a cache file the Claude Code statusline writes.

**Architecture:** A *producer* (Python helper invoked by the existing statusline script) writes account-level `rate_limits` to `~/.claude/usage-cache.json` via atomic rename. A *consumer* (SwiftPM macOS app) reads that file, watches it for changes, refreshes its display on a 10s local timer, and renders an `NSStatusItem` menu bar item plus a SwiftUI popover. All display logic lives in a pure, fully unit-tested `ClaudeUsageBarCore` library; the app shell wires it to AppKit/SwiftUI.

**Tech Stack:** Python 3 (producer); Swift 6 + SwiftPM (no Xcode required) with AppKit `NSStatusItem`, SwiftUI via `NSHostingView`/`NSPopover`, `XCTest` for the core library, and a LaunchAgent plist for launch-at-login.

**Toolchain note:** This machine has Command Line Tools only (no Xcode). The spec named SwiftUI `MenuBarExtra`; that Scene requires the Xcode app-bundle workflow. We achieve the identical UX (native menu bar item + popover, no Dock icon) using AppKit `NSStatusItem` + `NSPopover` hosting SwiftUI content, buildable with `swift build`. This is an implementation-level substitution, not a UX change.

---

## File Structure

**Producer (in repo, under `tracker/producer/`):**
- `tracker/producer/write_usage_cache.py` — reads statusline JSON on stdin, extracts `rate_limits`, writes `~/.claude/usage-cache.json` atomically. Output path overridable via `CLAUDE_USAGE_CACHE_PATH` env (for tests).
- `tracker/producer/tests/test_write_usage_cache.py` — pytest-free stdlib `unittest` tests.
- `~/.claude/statusline-command.sh` — **modify** to invoke the producer (one added block).
- `~/.claude/settings.json` (or `.claude/settings.local.json` in repo) — **modify** to add `statusLine.refreshInterval: 10`.

**Consumer SwiftPM package (under `tracker/app/ClaudeUsageBar/`):**
- `Package.swift` — declares `ClaudeUsageBarCore` (library), `ClaudeUsageBar` (executable), `ClaudeUsageBarCoreTests` (test target).
- `Sources/ClaudeUsageBarCore/CacheSchema.swift` — `Decodable` DTOs for the JSON file.
- `Sources/ClaudeUsageBarCore/UsageModel.swift` — domain types `UsageWindow`, `UsageSnapshot`, and mapping from the DTO.
- `Sources/ClaudeUsageBarCore/ResetFormatter.swift` — formats a reset `Date` to clock text (12h/24h, same-day vs other-day).
- `Sources/ClaudeUsageBarCore/UsageLevel.swift` — color-threshold classification.
- `Sources/ClaudeUsageBarCore/SnapshotEvaluator.swift` — stale + passed-reset evaluation → `EvaluatedSnapshot`.
- `Sources/ClaudeUsageBarCore/MonotonicSnapshotGate.swift` — rejects `captured_at` regressions.
- `Sources/ClaudeUsageBarCore/MenuBarTextBuilder.swift` — composes the menu bar string.
- `Sources/ClaudeUsageBar/CacheFileReader.swift` — reads+decodes the file, keeps last good snapshot.
- `Sources/ClaudeUsageBar/Settings.swift` — `UserDefaults`-backed settings.
- `Sources/ClaudeUsageBar/UsageViewModel.swift` — `ObservableObject` tying reader+gate+evaluator+timer.
- `Sources/ClaudeUsageBar/CacheFileWatcher.swift` — `DispatchSource` file watcher.
- `Sources/ClaudeUsageBar/OAuthRefreshClient.swift` — manual API refresh behind a protocol seam.
- `Sources/ClaudeUsageBar/KeychainTokenProvider.swift` — reads the OAuth token (best-effort).
- `Sources/ClaudeUsageBar/DropdownView.swift` — SwiftUI minimal popover.
- `Sources/ClaudeUsageBar/LaunchAgent.swift` — LaunchAgent plist generation + install.
- `Sources/ClaudeUsageBar/AppDelegate.swift` — `NSStatusItem`, popover, lifecycle wiring.
- `Sources/ClaudeUsageBar/main.swift` — `@main` entry, accessory activation policy.
- `Tests/ClaudeUsageBarCoreTests/*.swift` — one test file per core source.
- `tracker/app/package_app.sh` — wraps the built binary into `ClaudeUsageBar.app` (Info.plist `LSUIElement`).

---

## Task 1: Producer — usage-cache writer (Python)

**Files:**
- Create: `tracker/producer/write_usage_cache.py`
- Test: `tracker/producer/tests/test_write_usage_cache.py`

- [ ] **Step 1: Write the failing test**

Create `tracker/producer/tests/test_write_usage_cache.py`:

```python
import json, os, subprocess, sys, tempfile, unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "write_usage_cache.py"

def run(stdin_text, out_path):
    env = dict(os.environ, CLAUDE_USAGE_CACHE_PATH=str(out_path))
    return subprocess.run([sys.executable, str(SCRIPT)], input=stdin_text,
                          text=True, capture_output=True, env=env)

class WriteUsageCacheTest(unittest.TestCase):
    def test_writes_expected_shape(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            payload = json.dumps({"rate_limits": {
                "five_hour": {"used_percentage": 42.0, "resets_at": 1780041720},
                "seven_day": {"used_percentage": 18.0, "resets_at": 1780300800}}})
            r = run(payload, out)
            self.assertEqual(r.returncode, 0, r.stderr)
            data = json.loads(out.read_text())
            self.assertEqual(data["schema"], 1)
            self.assertIsInstance(data["captured_at"], int)
            self.assertEqual(data["five_hour"]["used_percentage"], 42.0)
            self.assertEqual(data["five_hour"]["resets_at"], 1780041720)
            self.assertEqual(data["seven_day"]["used_percentage"], 18.0)

    def test_no_tmp_residue(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            run(json.dumps({"rate_limits": {"five_hour": {"used_percentage": 1.0, "resets_at": 1}}}), out)
            leftovers = [p.name for p in Path(d).iterdir() if ".tmp" in p.name]
            self.assertEqual(leftovers, [])

    def test_missing_rate_limits_writes_nothing_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            r = run(json.dumps({"model": {"id": "x"}}), out)
            self.assertEqual(r.returncode, 0)
            self.assertFalse(out.exists())

    def test_invalid_json_exits_zero_no_file(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "usage-cache.json"
            r = run("not json", out)
            self.assertEqual(r.returncode, 0)
            self.assertFalse(out.exists())

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest discover -s tracker/producer/tests -v`
Expected: FAIL — `write_usage_cache.py` does not exist (subprocess returns nonzero / file not found).

- [ ] **Step 3: Write minimal implementation**

Create `tracker/producer/write_usage_cache.py`:

```python
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
    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".usage-cache.", suffix=".tmp",
                               dir=os.path.dirname(target))
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest discover -s tracker/producer/tests -v`
Expected: PASS (4 tests OK).

- [ ] **Step 5: Commit**

```bash
git add tracker/producer/write_usage_cache.py tracker/producer/tests/test_write_usage_cache.py
git commit -m "feat: usage-cache writer for statusline (atomic, tested)"
```

---

## Task 2: Wire producer into statusline + enable refreshInterval

**Files:**
- Modify: `~/.claude/statusline-command.sh` (add invocation after line 2 `input=$(cat ...)`)
- Modify: `.claude/settings.local.json` (add `statusLine.refreshInterval`)

> **Note:** The producer script lives in the repo at `tracker/producer/write_usage_cache.py`. The statusline references it by absolute path. Adjust the path below to the absolute repo path on the target machine (here: `/Users/bytedance/cc/tracker/producer/write_usage_cache.py`).

- [ ] **Step 1: Verify the current statusline still works (baseline)**

Run:
```bash
echo '{"rate_limits":{"five_hour":{"used_percentage":42.0,"resets_at":9999999999}}}' | bash ~/.claude/statusline-command.sh
```
Expected: prints a status line ending with ` 5h:42.00%(...)`. (Confirms the script consumes stdin as expected.)

- [ ] **Step 2: Add the producer invocation**

In `~/.claude/statusline-command.sh`, immediately after line 2 (`input=$(cat 2>/dev/null)`), insert:

```bash

# Mirror account rate limits to the usage cache for ClaudeUsageBar (best-effort, backgrounded).
if [ -n "$input" ]; then
  printf '%s' "$input" | python3 /Users/bytedance/cc/tracker/producer/write_usage_cache.py >/dev/null 2>&1 &
fi
```

- [ ] **Step 3: Verify the cache file is written**

Run:
```bash
rm -f ~/.claude/usage-cache.json
echo '{"rate_limits":{"five_hour":{"used_percentage":42.0,"resets_at":9999999999},"seven_day":{"used_percentage":18.0,"resets_at":9999999999}}}' | bash ~/.claude/statusline-command.sh >/dev/null
sleep 1
cat ~/.claude/usage-cache.json
```
Expected: JSON with `"schema":1`, `captured_at`, `five_hour`, `seven_day`. No `.tmp` file remains in `~/.claude/` (`ls ~/.claude/.usage-cache.*.tmp 2>/dev/null` prints nothing).

- [ ] **Step 4: Enable periodic statusline refresh**

In `.claude/settings.local.json`, set the `statusLine` block to include `refreshInterval`:

```json
"statusLine": {
  "type": "command",
  "command": "bash .claude/statusline-command.sh",
  "refreshInterval": 10
}
```

(If the user's active statusline is the global `~/.claude/statusline-command.sh`, mirror the same `refreshInterval` into the settings file that registers it.)

- [ ] **Step 5: Commit**

```bash
git add .claude/settings.local.json
git commit -m "feat: statusline writes usage cache + 10s refreshInterval"
```

(The `~/.claude/statusline-command.sh` edit is outside the repo; note it in the commit body as a manual host change if that file is not tracked here.)

---

## Task 3: SwiftPM package scaffold

**Files:**
- Create: `tracker/app/ClaudeUsageBar/Package.swift`
- Create: `tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/Placeholder.swift`
- Create: `tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/main.swift`
- Create: `tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write the failing test (smoke)**

Create `Tests/ClaudeUsageBarCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class SmokeTests: XCTestCase {
    func testCoreVersion() {
        XCTAssertEqual(ClaudeUsageBarCore.version, "0.1.0")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test`
Expected: FAIL — no `Package.swift` / no `ClaudeUsageBarCore` module yet.

- [ ] **Step 3: Write minimal implementation**

Create `Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeUsageBarCore"),
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageBarCore"]),
        .testTarget(
            name: "ClaudeUsageBarCoreTests",
            dependencies: ["ClaudeUsageBarCore"]),
    ]
)
```

Create `Sources/ClaudeUsageBarCore/Placeholder.swift`:

```swift
public enum ClaudeUsageBarCore {
    public static let version = "0.1.0"
}
```

Create `Sources/ClaudeUsageBar/main.swift`:

```swift
import ClaudeUsageBarCore
// Real entry point added in Task 11. Keep buildable for now.
print("ClaudeUsageBar core \(ClaudeUsageBarCore.version)")
```

- [ ] **Step 4: Run test + build to verify pass**

Run: `cd tracker/app/ClaudeUsageBar && swift test && swift build`
Expected: test PASS; build succeeds.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar
git commit -m "chore: scaffold ClaudeUsageBar SwiftPM package"
```

---

## Task 4: Cache file decoding (CacheSchema)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/CacheSchema.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/CacheSchemaTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/CacheSchemaTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class CacheSchemaTests: XCTestCase {
    private func decode(_ s: String) throws -> UsageCacheFile {
        try JSONDecoder().decode(UsageCacheFile.self, from: Data(s.utf8))
    }

    func testDecodesFullFile() throws {
        let f = try decode(#"{"schema":1,"captured_at":1780040000,"five_hour":{"used_percentage":42.0,"resets_at":1780041720},"seven_day":{"used_percentage":18.0,"resets_at":1780300800}}"#)
        XCTAssertEqual(f.schema, 1)
        XCTAssertEqual(f.capturedAt, 1780040000)
        XCTAssertEqual(f.fiveHour?.usedPercentage, 42.0)
        XCTAssertEqual(f.fiveHour?.resetsAt, 1780041720)
        XCTAssertEqual(f.sevenDay?.usedPercentage, 18.0)
    }

    func testDecodesWithMissingWindow() throws {
        let f = try decode(#"{"schema":1,"captured_at":1,"five_hour":{"used_percentage":5.0,"resets_at":2}}"#)
        XCTAssertNil(f.sevenDay)
        XCTAssertEqual(f.fiveHour?.usedPercentage, 5.0)
    }

    func testDecodesWindowMissingFields() throws {
        let f = try decode(#"{"schema":1,"captured_at":1,"five_hour":{}}"#)
        XCTAssertNil(f.fiveHour?.usedPercentage)
        XCTAssertNil(f.fiveHour?.resetsAt)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter CacheSchemaTests`
Expected: FAIL — `UsageCacheFile` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/CacheSchema.swift`:

```swift
import Foundation

public struct RateLimitWindowDTO: Decodable, Equatable {
    public let usedPercentage: Double?
    public let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

public struct UsageCacheFile: Decodable, Equatable {
    public let schema: Int
    public let capturedAt: Double
    public let fiveHour: RateLimitWindowDTO?
    public let sevenDay: RateLimitWindowDTO?

    enum CodingKeys: String, CodingKey {
        case schema
        case capturedAt = "captured_at"
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter CacheSchemaTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/CacheSchema.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/CacheSchemaTests.swift
git commit -m "feat: decode usage-cache JSON schema"
```

---

## Task 5: Domain model + mapping (UsageModel)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/UsageModel.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/UsageModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/UsageModelTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class UsageModelTests: XCTestCase {
    func testMapsBothWindows() {
        let file = UsageCacheFile(
            schema: 1, capturedAt: 1780040000,
            fiveHour: .init(usedPercentage: 42.0, resetsAt: 1780041720),
            sevenDay: .init(usedPercentage: 18.0, resetsAt: 1780300800))
        let snap = UsageSnapshot(file: file)
        XCTAssertEqual(snap.capturedAt, Date(timeIntervalSince1970: 1780040000))
        XCTAssertEqual(snap.fiveHour?.usedPercentage, 42.0)
        XCTAssertEqual(snap.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1780041720))
        XCTAssertEqual(snap.sevenDay?.usedPercentage, 18.0)
    }

    func testWindowDroppedWhenFieldMissing() {
        let file = UsageCacheFile(
            schema: 1, capturedAt: 1,
            fiveHour: .init(usedPercentage: 42.0, resetsAt: nil),
            sevenDay: nil)
        let snap = UsageSnapshot(file: file)
        XCTAssertNil(snap.fiveHour)   // resets_at missing -> not a usable window
        XCTAssertNil(snap.sevenDay)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter UsageModelTests`
Expected: FAIL — `UsageSnapshot` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/UsageModel.swift`:

```swift
import Foundation

public struct UsageWindow: Equatable {
    public let usedPercentage: Double
    public let resetsAt: Date
    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable {
    public let capturedAt: Date
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?

    public init(capturedAt: Date, fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public init(file: UsageCacheFile) {
        self.capturedAt = Date(timeIntervalSince1970: file.capturedAt)
        self.fiveHour = UsageSnapshot.window(file.fiveHour)
        self.sevenDay = UsageSnapshot.window(file.sevenDay)
    }

    private static func window(_ dto: RateLimitWindowDTO?) -> UsageWindow? {
        guard let dto, let pct = dto.usedPercentage, let reset = dto.resetsAt else {
            return nil
        }
        return UsageWindow(usedPercentage: pct, resetsAt: Date(timeIntervalSince1970: reset))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter UsageModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/UsageModel.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/UsageModelTests.swift
git commit -m "feat: usage domain model + DTO mapping"
```

---

## Task 6: Reset time formatting (ResetFormatter)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/ResetFormatter.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/ResetFormatterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/ResetFormatterTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class ResetFormatterTests: XCTestCase {
    private func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
    // Reference "now": 2026-05-29 12:30:00 UTC (a Friday).
    private let now = Date(timeIntervalSince1970: 1780057800)

    func testSameDay24h() {
        let f = ResetFormatter(clock: .twentyFourHour, calendar: calendar())
        // 2026-05-29 15:42:00 UTC
        let reset = Date(timeIntervalSince1970: 1780069320)
        XCTAssertEqual(f.string(for: reset, now: now), "15:42")
    }

    func testOtherDay24h() {
        let f = ResetFormatter(clock: .twentyFourHour, calendar: calendar())
        // 2026-05-31 16:00:00 UTC (Sunday)
        let reset = Date(timeIntervalSince1970: 1780243200)
        XCTAssertEqual(f.string(for: reset, now: now), "Sun 16:00")
    }

    func testSameDay12h() {
        let f = ResetFormatter(clock: .twelveHour, calendar: calendar())
        let reset = Date(timeIntervalSince1970: 1780069320) // 15:42
        XCTAssertEqual(f.string(for: reset, now: now), "3:42 PM")
    }

    func testOtherDay12h() {
        let f = ResetFormatter(clock: .twelveHour, calendar: calendar())
        let reset = Date(timeIntervalSince1970: 1780243200) // Sun 16:00
        XCTAssertEqual(f.string(for: reset, now: now), "Sun 4:00 PM")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter ResetFormatterTests`
Expected: FAIL — `ResetFormatter` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/ResetFormatter.swift`:

```swift
import Foundation

public struct ResetFormatter {
    public enum Clock { case twelveHour, twentyFourHour }

    private let clock: Clock
    private let calendar: Calendar

    public init(clock: Clock, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    public func string(for resetDate: Date, now: Date) -> String {
        let sameDay = calendar.isDate(resetDate, inSameDayAs: now)
        let timePart: String
        switch clock {
        case .twentyFourHour: timePart = format(resetDate, "HH:mm")
        case .twelveHour:     timePart = format(resetDate, "h:mm a")
        }
        if sameDay { return timePart }
        return format(resetDate, "EEE") + " " + timePart
    }

    private func format(_ date: Date, _ template: String) -> String {
        let df = DateFormatter()
        df.calendar = calendar
        df.locale = calendar.locale ?? Locale(identifier: "en_US_POSIX")
        df.timeZone = calendar.timeZone
        df.dateFormat = template
        return df.string(from: date)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter ResetFormatterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/ResetFormatter.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/ResetFormatterTests.swift
git commit -m "feat: reset-time formatter (12h/24h, same-day vs weekday)"
```

---

## Task 7: Color-threshold classification (UsageLevel)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/UsageLevel.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/UsageLevelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/UsageLevelTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class UsageLevelTests: XCTestCase {
    func testThresholds() {
        XCTAssertEqual(UsageLevel(percentage: 0), .low)
        XCTAssertEqual(UsageLevel(percentage: 49.9), .low)
        XCTAssertEqual(UsageLevel(percentage: 50), .medium)
        XCTAssertEqual(UsageLevel(percentage: 79.9), .medium)
        XCTAssertEqual(UsageLevel(percentage: 80), .high)
        XCTAssertEqual(UsageLevel(percentage: 100), .high)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter UsageLevelTests`
Expected: FAIL — `UsageLevel` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/UsageLevel.swift`:

```swift
public enum UsageLevel: Equatable {
    case low      // green  (<50%)
    case medium   // yellow (50–80%)
    case high     // red    (>80%, i.e. >=80)

    public init(percentage: Double) {
        if percentage >= 80 { self = .high }
        else if percentage >= 50 { self = .medium }
        else { self = .low }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter UsageLevelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/UsageLevel.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/UsageLevelTests.swift
git commit -m "feat: usage-level color thresholds"
```

---

## Task 8: Stale + passed-reset evaluation (SnapshotEvaluator)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/SnapshotEvaluator.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/SnapshotEvaluatorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/SnapshotEvaluatorTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class SnapshotEvaluatorTests: XCTestCase {
    private let eval = SnapshotEvaluator(staleAfter: 1800) // 30 min

    func testFreshWindowPassthrough() {
        let now = Date(timeIntervalSince1970: 1000)
        let snap = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 940), // 60s ago
            fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 5000)),
            sevenDay: nil)
        let e = eval.evaluate(snap, now: now)
        XCTAssertEqual(e.fiveHour?.usedPercentage, 42)
        XCTAssertEqual(e.fiveHour?.isStale, false)
        XCTAssertEqual(e.fiveHour?.didReset, false)
    }

    func testStaleWhenOld() {
        let now = Date(timeIntervalSince1970: 5000)
        let snap = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1000), // 4000s ago > 1800
            fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 9000)),
            sevenDay: nil)
        let e = eval.evaluate(snap, now: now)
        XCTAssertEqual(e.fiveHour?.isStale, true)
    }

    func testPassedResetZeroesPercentage() {
        let now = Date(timeIntervalSince1970: 5000)
        let snap = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 4990),
            fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 4000)), // past
            sevenDay: nil)
        let e = eval.evaluate(snap, now: now)
        XCTAssertEqual(e.fiveHour?.usedPercentage, 0)
        XCTAssertEqual(e.fiveHour?.didReset, true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter SnapshotEvaluatorTests`
Expected: FAIL — `SnapshotEvaluator` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/SnapshotEvaluator.swift`:

```swift
import Foundation

public struct DisplayWindow: Equatable {
    public let usedPercentage: Double
    public let resetsAt: Date
    public let isStale: Bool
    public let didReset: Bool
}

public struct EvaluatedSnapshot: Equatable {
    public let capturedAt: Date
    public let fiveHour: DisplayWindow?
    public let sevenDay: DisplayWindow?
}

public struct SnapshotEvaluator {
    private let staleAfter: TimeInterval

    public init(staleAfter: TimeInterval) {
        self.staleAfter = staleAfter
    }

    public func evaluate(_ snapshot: UsageSnapshot, now: Date) -> EvaluatedSnapshot {
        let stale = now.timeIntervalSince(snapshot.capturedAt) > staleAfter
        return EvaluatedSnapshot(
            capturedAt: snapshot.capturedAt,
            fiveHour: display(snapshot.fiveHour, stale: stale, now: now),
            sevenDay: display(snapshot.sevenDay, stale: stale, now: now))
    }

    private func display(_ w: UsageWindow?, stale: Bool, now: Date) -> DisplayWindow? {
        guard let w else { return nil }
        let didReset = w.resetsAt <= now
        return DisplayWindow(
            usedPercentage: didReset ? 0 : w.usedPercentage,
            resetsAt: w.resetsAt,
            isStale: stale,
            didReset: didReset)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter SnapshotEvaluatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/SnapshotEvaluator.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/SnapshotEvaluatorTests.swift
git commit -m "feat: snapshot evaluator (stale + passed-reset)"
```

---

## Task 9: Monotonic captured_at gate (MonotonicSnapshotGate)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/MonotonicSnapshotGate.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/MonotonicSnapshotGateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/MonotonicSnapshotGateTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class MonotonicSnapshotGateTests: XCTestCase {
    private func snap(_ t: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(capturedAt: Date(timeIntervalSince1970: t), fiveHour: nil, sevenDay: nil)
    }

    func testAcceptsFirstAndNewer() {
        let gate = MonotonicSnapshotGate()
        XCTAssertTrue(gate.accept(snap(100)))
        XCTAssertTrue(gate.accept(snap(200)))
    }

    func testRejectsOlderOrEqual() {
        let gate = MonotonicSnapshotGate()
        XCTAssertTrue(gate.accept(snap(200)))
        XCTAssertFalse(gate.accept(snap(150)))
        XCTAssertFalse(gate.accept(snap(200)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter MonotonicSnapshotGateTests`
Expected: FAIL — `MonotonicSnapshotGate` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/MonotonicSnapshotGate.swift`:

```swift
import Foundation

public final class MonotonicSnapshotGate {
    private var last: Date?

    public init() {}

    /// Returns true and records the snapshot if it is strictly newer than the
    /// last accepted one; otherwise returns false and ignores it.
    public func accept(_ snapshot: UsageSnapshot) -> Bool {
        if let last, snapshot.capturedAt <= last { return false }
        last = snapshot.capturedAt
        return true
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter MonotonicSnapshotGateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/MonotonicSnapshotGate.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/MonotonicSnapshotGateTests.swift
git commit -m "feat: monotonic captured_at gate"
```

---

## Task 10: Menu bar text composition (MenuBarTextBuilder)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/MenuBarTextBuilder.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/MenuBarTextBuilderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/MenuBarTextBuilderTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class MenuBarTextBuilderTests: XCTestCase {
    private func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
    private let now = Date(timeIntervalSince1970: 1780057800) // 2026-05-29 12:30 UTC Fri

    func testBothWindows24h() {
        let b = MenuBarTextBuilder(formatter: ResetFormatter(clock: .twentyFourHour, calendar: calendar()))
        let e = EvaluatedSnapshot(
            capturedAt: now,
            fiveHour: DisplayWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1780069320), isStale: false, didReset: false),
            sevenDay: DisplayWindow(usedPercentage: 18, resetsAt: Date(timeIntervalSince1970: 1780243200), isStale: false, didReset: false))
        XCTAssertEqual(b.text(for: e, now: now), "42% →15:42  18% →Sun 16:00")
    }

    func testMissingWindowShowsDash() {
        let b = MenuBarTextBuilder(formatter: ResetFormatter(clock: .twentyFourHour, calendar: calendar()))
        let e = EvaluatedSnapshot(capturedAt: now, fiveHour: nil, sevenDay: nil)
        XCTAssertEqual(b.text(for: e, now: now), "—")
    }

    func testRoundsPercentage() {
        let b = MenuBarTextBuilder(formatter: ResetFormatter(clock: .twentyFourHour, calendar: calendar()))
        let e = EvaluatedSnapshot(
            capturedAt: now,
            fiveHour: DisplayWindow(usedPercentage: 42.7, resetsAt: Date(timeIntervalSince1970: 1780069320), isStale: false, didReset: false),
            sevenDay: nil)
        XCTAssertEqual(b.text(for: e, now: now), "43% →15:42")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter MenuBarTextBuilderTests`
Expected: FAIL — `MenuBarTextBuilder` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/MenuBarTextBuilder.swift`:

```swift
import Foundation

public struct MenuBarTextBuilder {
    private let formatter: ResetFormatter

    public init(formatter: ResetFormatter) {
        self.formatter = formatter
    }

    public func text(for snapshot: EvaluatedSnapshot, now: Date) -> String {
        let parts = [snapshot.fiveHour, snapshot.sevenDay]
            .compactMap { $0 }
            .map { segment(for: $0, now: now) }
        return parts.isEmpty ? "—" : parts.joined(separator: "  ")
    }

    private func segment(for w: DisplayWindow, now: Date) -> String {
        let pct = Int(w.usedPercentage.rounded())
        let reset = formatter.string(for: w.resetsAt, now: now)
        return "\(pct)% →\(reset)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter MenuBarTextBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/MenuBarTextBuilder.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/MenuBarTextBuilderTests.swift
git commit -m "feat: menu bar text builder"
```

---

## Task 11: Cache file reader (CacheFileReader)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/CacheFileReader.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/CacheFileReaderTests.swift`

> **Decomposition note:** `CacheFileReader` decodes a file path into a `UsageSnapshot?` and retains the last good snapshot. It uses only `ClaudeUsageBarCore` + Foundation, so the type lives in the Core library (testable) — *not* the executable target — and the executable only wires it to AppKit.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/CacheFileReaderTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class CacheFileReaderTests: XCTestCase {
    private func tempFile(_ contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccu-\(UUID().uuidString).json")
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsValidFile() {
        let url = tempFile(#"{"schema":1,"captured_at":1780040000,"five_hour":{"used_percentage":42.0,"resets_at":1780041720}}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = CacheFileReader(url: url)
        let snap = reader.read()
        XCTAssertEqual(snap?.fiveHour?.usedPercentage, 42.0)
    }

    func testMissingFileReturnsNil() {
        let reader = CacheFileReader(url: URL(fileURLWithPath: "/no/such/file.json"))
        XCTAssertNil(reader.read())
    }

    func testMalformedKeepsLastGood() {
        let good = tempFile(#"{"schema":1,"captured_at":1,"five_hour":{"used_percentage":5.0,"resets_at":2}}"#)
        defer { try? FileManager.default.removeItem(at: good) }
        let reader = CacheFileReader(url: good)
        _ = reader.read()                       // caches last good
        try? "garbage".write(to: good, atomically: true, encoding: .utf8)
        let snap = reader.read()
        XCTAssertEqual(snap?.fiveHour?.usedPercentage, 5.0) // last good retained
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter CacheFileReaderTests`
Expected: FAIL — `CacheFileReader` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/CacheFileReader.swift`:

```swift
import Foundation

public final class CacheFileReader {
    private let url: URL
    private var lastGood: UsageSnapshot?

    public init(url: URL) {
        self.url = url
    }

    /// Reads and decodes the cache file. On missing/malformed file returns the
    /// last good snapshot (nil if none yet).
    public func read() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(UsageCacheFile.self, from: data)
        else { return lastGood }
        let snapshot = UsageSnapshot(file: file)
        lastGood = snapshot
        return snapshot
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter CacheFileReaderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/CacheFileReader.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/CacheFileReaderTests.swift
git commit -m "feat: cache file reader with last-good retention"
```

---

## Task 12: Settings store (Settings)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/Settings.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/SettingsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/SettingsTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class SettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "ccu-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaults() {
        let s = Settings(defaults: freshDefaults())
        XCTAssertEqual(s.clock, .twentyFourHour)
        XCTAssertEqual(s.refreshInterval, 10)
        XCTAssertFalse(s.launchAtLogin)
    }

    func testPersistsChanges() {
        let d = freshDefaults()
        let s = Settings(defaults: d)
        s.clock = .twelveHour
        s.refreshInterval = 30
        s.launchAtLogin = true
        let reloaded = Settings(defaults: d)
        XCTAssertEqual(reloaded.clock, .twelveHour)
        XCTAssertEqual(reloaded.refreshInterval, 30)
        XCTAssertTrue(reloaded.launchAtLogin)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter SettingsTests`
Expected: FAIL — `Settings` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/Settings.swift`:

```swift
import Foundation

public final class Settings {
    private let defaults: UserDefaults
    private enum Key {
        static let clock = "clock"
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var clock: ResetFormatter.Clock {
        get { defaults.string(forKey: Key.clock) == "12" ? .twelveHour : .twentyFourHour }
        set { defaults.set(newValue == .twelveHour ? "12" : "24", forKey: Key.clock) }
    }

    public var refreshInterval: Int {
        get {
            let v = defaults.integer(forKey: Key.refreshInterval)
            return v == 0 ? 10 : v
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter SettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/Settings.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/SettingsTests.swift
git commit -m "feat: UserDefaults-backed settings"
```

---

## Task 13: View model (UsageViewModel)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/UsageViewModel.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/UsageViewModelTests.swift`

> The view model holds presentation state (menu bar text, the evaluated snapshot for the dropdown, "updated Ns ago"). It is driven by an injected `now` and an injected snapshot source so it is fully testable without timers or files.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/UsageViewModelTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class UsageViewModelTests: XCTestCase {
    private func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
    private let now = Date(timeIntervalSince1970: 1780057800)

    func testRefreshProducesMenuBarText() {
        let vm = UsageViewModel(
            formatter: ResetFormatter(clock: .twentyFourHour, calendar: calendar()),
            evaluator: SnapshotEvaluator(staleAfter: 1800))
        let snap = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1780057740), // 60s ago
            fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1780069320)),
            sevenDay: UsageWindow(usedPercentage: 18, resetsAt: Date(timeIntervalSince1970: 1780243200)))
        vm.apply(snapshot: snap, now: now)
        XCTAssertEqual(vm.menuBarText, "42% →15:42  18% →Sun 16:00")
        XCTAssertEqual(vm.updatedAgoText, "updated 1m ago")
    }

    func testNoDataText() {
        let vm = UsageViewModel(
            formatter: ResetFormatter(clock: .twentyFourHour, calendar: calendar()),
            evaluator: SnapshotEvaluator(staleAfter: 1800))
        vm.apply(snapshot: nil, now: now)
        XCTAssertEqual(vm.menuBarText, "—")
        XCTAssertNil(vm.evaluated)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter UsageViewModelTests`
Expected: FAIL — `UsageViewModel` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/UsageViewModel.swift`:

```swift
import Foundation
import Combine

public final class UsageViewModel: ObservableObject {
    @Published public private(set) var menuBarText: String = "—"
    @Published public private(set) var evaluated: EvaluatedSnapshot?
    @Published public private(set) var updatedAgoText: String = ""

    private let formatter: ResetFormatter
    private let evaluator: SnapshotEvaluator
    private let textBuilder: MenuBarTextBuilder

    public init(formatter: ResetFormatter, evaluator: SnapshotEvaluator) {
        self.formatter = formatter
        self.evaluator = evaluator
        self.textBuilder = MenuBarTextBuilder(formatter: formatter)
    }

    public func apply(snapshot: UsageSnapshot?, now: Date) {
        guard let snapshot else {
            menuBarText = "—"
            evaluated = nil
            updatedAgoText = "No data yet"
            return
        }
        let e = evaluator.evaluate(snapshot, now: now)
        evaluated = e
        menuBarText = textBuilder.text(for: e, now: now)
        updatedAgoText = "updated " + Self.ago(from: e.capturedAt, to: now)
    }

    static func ago(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        return "\(m / 60)h ago"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter UsageViewModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/UsageViewModel.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/UsageViewModelTests.swift
git commit -m "feat: usage view model (presentation state)"
```

---

## Task 14: App shell — NSStatusItem rendering menu bar text

**Files:**
- Create: `Sources/ClaudeUsageBar/AppDelegate.swift`
- Modify: `Sources/ClaudeUsageBar/main.swift`

> This task has no unit test (AppKit lifecycle); verification is by running the app and observing the menu bar. All logic it relies on is already tested in Core.

- [ ] **Step 1: Implement the app delegate**

Create `Sources/ClaudeUsageBar/AppDelegate.swift`:

```swift
import AppKit
import Combine
import ClaudeUsageBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let settings = Settings()
    private var viewModel: UsageViewModel!
    private var reader: CacheFileReader!
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var cacheURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/usage-cache.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let formatter = ResetFormatter(clock: settings.clock, calendar: .current)
        viewModel = UsageViewModel(formatter: formatter,
                                   evaluator: SnapshotEvaluator(staleAfter: 1800))
        reader = CacheFileReader(url: cacheURL)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        viewModel.$menuBarText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in self?.statusItem.button?.title = text }
            .store(in: &cancellables)

        refresh()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.refreshInterval),
                                     repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc private func refresh() {
        let snapshot = reader.read()
        viewModel.apply(snapshot: snapshot, now: Date())
    }
}
```

Replace `Sources/ClaudeUsageBar/main.swift` with:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon, menu bar only
app.run()
```

- [ ] **Step 2: Build**

Run: `cd tracker/app/ClaudeUsageBar && swift build`
Expected: build succeeds.

- [ ] **Step 3: Manual verification**

Run:
```bash
# Seed a cache file with a far-future reset so it renders.
python3 -c 'import json,time,os;open(os.path.expanduser("~/.claude/usage-cache.json"),"w").write(json.dumps({"schema":1,"captured_at":int(time.time()),"five_hour":{"used_percentage":42.0,"resets_at":int(time.time())+3600},"seven_day":{"used_percentage":18.0,"resets_at":int(time.time())+200000}}))'
cd tracker/app/ClaudeUsageBar && swift run
```
Expected: a menu bar item appears showing `42% →…  18% →…`. No Dock icon. Quit with Ctrl-C in the terminal.

- [ ] **Step 4: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/AppDelegate.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/main.swift
git commit -m "feat: menu bar app shell with 10s refresh timer"
```

---

## Task 15: File watcher (CacheFileWatcher)

**Files:**
- Create: `Sources/ClaudeUsageBar/CacheFileWatcher.swift`
- Modify: `Sources/ClaudeUsageBar/AppDelegate.swift` (wire watcher → refresh)

> Watches the cache file's directory for writes (the producer renames into it, so we watch the parent directory to catch the new inode). Verification is manual. The debounce delay is small and fixed.

- [ ] **Step 1: Implement the watcher**

Create `Sources/ClaudeUsageBar/CacheFileWatcher.swift`:

```swift
import Foundation

/// Watches a directory for changes and calls `onChange` (debounced) on the main queue.
/// We watch the directory (not the file) because atomic rename replaces the inode.
final class CacheFileWatcher {
    private let directoryURL: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1
    private var debounceWorkItem: DispatchWorkItem?

    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.onChange = onChange
    }

    func start() {
        fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .global())
        src.setEventHandler { [weak self] in self?.debouncedFire() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
        }
        source = src
        src.resume()
    }

    private func debouncedFire() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
```

- [ ] **Step 2: Wire into AppDelegate**

In `Sources/ClaudeUsageBar/AppDelegate.swift`, add a stored property near `timer`:

```swift
    private var watcher: CacheFileWatcher?
```

At the end of `applicationDidFinishLaunching(_:)`, after `startTimer()`, add:

```swift
        watcher = CacheFileWatcher(directoryURL: cacheURL.deletingLastPathComponent()) { [weak self] in
            self?.refresh()
        }
        watcher?.start()
```

- [ ] **Step 3: Build + manual verification**

Run: `cd tracker/app/ClaudeUsageBar && swift build && swift run`
Then in a second terminal, rewrite the cache file with a different percentage:
```bash
python3 -c 'import json,time,os;open(os.path.expanduser("~/.claude/usage-cache.json"),"w").write(json.dumps({"schema":1,"captured_at":int(time.time()),"five_hour":{"used_percentage":77.0,"resets_at":int(time.time())+3600}}))'
```
Expected: the menu bar item updates to `77% →…` within ~1s without waiting for the 10s timer.

- [ ] **Step 4: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/CacheFileWatcher.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/AppDelegate.swift
git commit -m "feat: live cache file watcher"
```

---

## Task 16: Dropdown popover (DropdownView)

**Files:**
- Create: `Sources/ClaudeUsageBar/DropdownView.swift`
- Modify: `Sources/ClaudeUsageBar/AppDelegate.swift` (popover + button action)

> Minimal layout: two windows (title, percent, progress bar, reset time), an "updated Ns ago" line, a Refresh button, and Quit. Color thresholds map `UsageLevel` → SwiftUI `Color`. Verification is manual.

- [ ] **Step 1: Implement the SwiftUI view**

Create `Sources/ClaudeUsageBar/DropdownView.swift`:

```swift
import SwiftUI
import ClaudeUsageBarCore

func color(for pct: Double) -> Color {
    switch UsageLevel(percentage: pct) {
    case .low: return .green
    case .medium: return .yellow
    case .high: return .red
    }
}

struct WindowRow: View {
    let title: String
    let window: DisplayWindow
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(window.usedPercentage.rounded()))%")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundColor(color(for: window.usedPercentage))
            }
            ProgressView(value: min(window.usedPercentage, 100), total: 100)
                .tint(color(for: window.usedPercentage))
            HStack(spacing: 6) {
                Text("resets \(resetText)").font(.system(size: 11.5)).foregroundColor(.secondary)
                if window.didReset { Circle().fill(Color.yellow).frame(width: 6, height: 6) }
                if window.isStale { Text("· stale").font(.system(size: 10.5)).foregroundColor(.secondary) }
            }
        }
    }
}

struct DropdownView: View {
    @ObservedObject var viewModel: UsageViewModel
    let resetText: (Date) -> String
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let e = viewModel.evaluated {
                if let fh = e.fiveHour { WindowRow(title: "5-hour", window: fh, resetText: resetText(fh.resetsAt)) }
                if let sd = e.sevenDay { WindowRow(title: "Weekly", window: sd, resetText: resetText(sd.resetsAt)) }
            } else {
                Text("No data yet — use Claude Code once to populate.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Divider()
            HStack {
                Text(viewModel.updatedAgoText).font(.system(size: 11.5)).foregroundColor(.secondary)
                Spacer()
                Button("Refresh", action: onRefresh).font(.system(size: 11.5))
                Button("Quit", action: onQuit).font(.system(size: 11.5))
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
```

- [ ] **Step 2: Wire popover into AppDelegate**

In `Sources/ClaudeUsageBar/AppDelegate.swift`, add imports at top:

```swift
import SwiftUI
```

Add stored properties:

```swift
    private var popover: NSPopover!
```

At the end of `applicationDidFinishLaunching(_:)`, after wiring the watcher, add:

```swift
        let formatterForView = ResetFormatter(clock: settings.clock, calendar: .current)
        let content = DropdownView(
            viewModel: viewModel,
            resetText: { date in formatterForView.string(for: date, now: Date()) },
            onRefresh: { [weak self] in self?.refresh() },
            onQuit: { NSApp.terminate(nil) })
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: content)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
```

Add the toggle method:

```swift
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
```

- [ ] **Step 3: Build + manual verification**

Run: `cd tracker/app/ClaudeUsageBar && swift build && swift run`
Expected: clicking the menu bar item opens a 300px-wide popover with two progress bars, "updated Ns ago", Refresh, and Quit. Quit terminates the app.

- [ ] **Step 4: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/DropdownView.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/AppDelegate.swift
git commit -m "feat: minimal dropdown popover"
```

---

## Task 17: OAuth refresh client (OAuthRefreshClient)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/OAuthRefreshClient.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/OAuthRefreshClientTests.swift`

> Behind a protocol seam (`HTTPFetching`) so the 429 / success / no-token branches are unit-testable without network. Parses the response into a `UsageCacheFile` (reusing the same schema). The exact response shape is undocumented; the parser tolerates the same field names as the cache file and is the single place to adjust if the live shape differs.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeUsageBarCoreTests/OAuthRefreshClientTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

private final class StubFetcher: HTTPFetching {
    var result: Result<(Data, Int), Error>
    init(_ r: Result<(Data, Int), Error>) { result = r }
    func get(url: URL, bearer: String) async throws -> (Data, Int) {
        switch result {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}

final class OAuthRefreshClientTests: XCTestCase {
    func testSuccessParsesSnapshot() async throws {
        let body = #"{"five_hour":{"used_percentage":55.0,"resets_at":1780069320},"seven_day":{"used_percentage":12.0,"resets_at":1780243200}}"#
        let client = OAuthRefreshClient(fetcher: StubFetcher(.success((Data(body.utf8), 200))),
                                        url: URL(string: "https://example.com")!)
        let outcome = try await client.refresh(token: "tok")
        if case .success(let snap) = outcome {
            XCTAssertEqual(snap.fiveHour?.usedPercentage, 55.0)
        } else { XCTFail("expected success, got \(outcome)") }
    }

    func testRateLimited() async throws {
        let client = OAuthRefreshClient(fetcher: StubFetcher(.success((Data(), 429))),
                                        url: URL(string: "https://example.com")!)
        let outcome = try await client.refresh(token: "tok")
        XCTAssertEqual(outcome, .rateLimited)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter OAuthRefreshClientTests`
Expected: FAIL — `OAuthRefreshClient` / `HTTPFetching` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/OAuthRefreshClient.swift`:

```swift
import Foundation

public protocol HTTPFetching {
    func get(url: URL, bearer: String) async throws -> (Data, Int)
}

public enum RefreshOutcome: Equatable {
    case success(UsageSnapshot)
    case rateLimited
    case failed
}

public struct OAuthRefreshClient {
    private let fetcher: HTTPFetching
    private let url: URL

    public init(fetcher: HTTPFetching, url: URL) {
        self.fetcher = fetcher
        self.url = url
    }

    public func refresh(token: String) async throws -> RefreshOutcome {
        let (data, status) = try await fetcher.get(url: url, bearer: token)
        if status == 429 { return .rateLimited }
        guard status == 200 else { return .failed }
        // The live response uses the same window field names as the cache file.
        struct Body: Decodable {
            let five_hour: RateLimitWindowDTO?
            let seven_day: RateLimitWindowDTO?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return .failed }
        let file = UsageCacheFile(schema: 1, capturedAt: Date().timeIntervalSince1970,
                                  fiveHour: body.five_hour, sevenDay: body.seven_day)
        return .success(UsageSnapshot(file: file))
    }
}
```

> Note: `RefreshOutcome` conforms to `Equatable`; `UsageSnapshot` already is, so the synthesized conformance holds.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter OAuthRefreshClientTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/OAuthRefreshClient.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/OAuthRefreshClientTests.swift
git commit -m "feat: 429-tolerant OAuth refresh client (testable)"
```

---

## Task 18: Keychain token + real HTTP fetcher, wired to Refresh button

**Files:**
- Create: `Sources/ClaudeUsageBar/KeychainTokenProvider.swift`
- Create: `Sources/ClaudeUsageBar/URLSessionFetcher.swift`
- Modify: `Sources/ClaudeUsageBar/AppDelegate.swift` (Refresh button calls the client)

> No unit test (Keychain + live URLSession). Best-effort: if the token is unavailable, the Refresh action surfaces a message and does nothing destructive. The exact Keychain service/account names are confirmed at this step (Open Risk in spec §13).

- [ ] **Step 1: Implement the Keychain token provider**

Create `Sources/ClaudeUsageBar/KeychainTokenProvider.swift`:

```swift
import Foundation
import Security

enum KeychainTokenProvider {
    /// Best-effort lookup of the Claude Code OAuth token from the login keychain.
    /// Service/account names confirmed during implementation; returns nil if absent.
    static func token(service: String = "Claude Code-credentials") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        // Stored value may be JSON; extract an access token field if present, else use raw.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["accessToken"] as? String { return t }
            if let nested = json["claudeAiOauth"] as? [String: Any],
               let t = nested["accessToken"] as? String { return t }
        }
        return raw
    }
}
```

- [ ] **Step 2: Implement the URLSession fetcher**

Create `Sources/ClaudeUsageBar/URLSessionFetcher.swift`:

```swift
import Foundation
import ClaudeUsageBarCore

struct URLSessionFetcher: HTTPFetching {
    func get(url: URL, bearer: String) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}
```

- [ ] **Step 3: Wire the Refresh button**

In `Sources/ClaudeUsageBar/AppDelegate.swift`, add an import:

```swift
import ClaudeUsageBarCore
```

Add a method:

```swift
    private static let oauthUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    @objc private func refreshFromAPI() {
        guard let token = KeychainTokenProvider.token() else {
            viewModel.note("Sign in to Claude Code first")
            return
        }
        let client = OAuthRefreshClient(fetcher: URLSessionFetcher(), url: Self.oauthUsageURL)
        Task { @MainActor in
            let outcome = (try? await client.refresh(token: token)) ?? .failed
            switch outcome {
            case .success(let snap): self.viewModel.apply(snapshot: snap, now: Date())
            case .rateLimited: self.viewModel.note("Rate-limited, try later")
            case .failed: self.viewModel.note("Refresh failed")
            }
        }
    }
```

Change the popover's `onRefresh` closure (in `applicationDidFinishLaunching`) from `self?.refresh()` to `self?.refreshFromAPI()`.

- [ ] **Step 4: Add `note(_:)` to the view model**

In `Sources/ClaudeUsageBarCore/UsageViewModel.swift`, add a published property and method:

```swift
    @Published public private(set) var noteText: String?

    public func note(_ message: String) {
        noteText = message
    }
```

And in `DropdownView.swift`, show it under the footer when present:

```swift
            if let note = viewModel.noteText {
                Text(note).font(.system(size: 11)).foregroundColor(.orange)
            }
```

(Place this line inside the outer `VStack`, just before the closing of the `body`'s `VStack`.)

- [ ] **Step 5: Build + manual verification**

Run: `cd tracker/app/ClaudeUsageBar && swift build && swift run`
Expected: clicking **Refresh** either updates the numbers (200), or shows "Rate-limited, try later" (429), or "Sign in to Claude Code first" (no token). It never spins or blocks the UI.

- [ ] **Step 6: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/KeychainTokenProvider.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/URLSessionFetcher.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/AppDelegate.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/UsageViewModel.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/DropdownView.swift
git commit -m "feat: manual API refresh via Keychain token"
```

---

## Task 19: Launch-at-login (LaunchAgent)

**Files:**
- Create: `Sources/ClaudeUsageBarCore/LaunchAgentPlist.swift`
- Test: `Tests/ClaudeUsageBarCoreTests/LaunchAgentPlistTests.swift`
- Create: `Sources/ClaudeUsageBar/LaunchAgentInstaller.swift`
- Modify: `Sources/ClaudeUsageBar/AppDelegate.swift` (apply on launch per setting)

> The plist *generation* is pure and tested. The install/uninstall (writing to `~/Library/LaunchAgents`) is thin AppKit-free file IO, verified manually.

- [ ] **Step 1: Write the failing test for plist generation**

Create `Tests/ClaudeUsageBarCoreTests/LaunchAgentPlistTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBarCore

final class LaunchAgentPlistTests: XCTestCase {
    func testContainsLabelAndProgram() {
        let xml = LaunchAgentPlist.xml(label: "com.claudeusagebar.agent",
                                       programPath: "/Applications/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar")
        XCTAssertTrue(xml.contains("<key>Label</key>"))
        XCTAssertTrue(xml.contains("<string>com.claudeusagebar.agent</string>"))
        XCTAssertTrue(xml.contains("/Applications/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar"))
        XCTAssertTrue(xml.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(xml.hasPrefix("<?xml"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter LaunchAgentPlistTests`
Expected: FAIL — `LaunchAgentPlist` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeUsageBarCore/LaunchAgentPlist.swift`:

```swift
public enum LaunchAgentPlist {
    public static func xml(label: String, programPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(programPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd tracker/app/ClaudeUsageBar && swift test --filter LaunchAgentPlistTests`
Expected: PASS.

- [ ] **Step 5: Implement the installer**

Create `Sources/ClaudeUsageBar/LaunchAgentInstaller.swift`:

```swift
import Foundation
import ClaudeUsageBarCore

enum LaunchAgentInstaller {
    static let label = "com.claudeusagebar.agent"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func apply(enabled: Bool, programPath: String) {
        if enabled {
            let xml = LaunchAgentPlist.xml(label: label, programPath: programPath)
            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? xml.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
```

- [ ] **Step 6: Apply setting on launch**

In `Sources/ClaudeUsageBar/AppDelegate.swift`, at the end of `applicationDidFinishLaunching(_:)`, add:

```swift
        let exePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        LaunchAgentInstaller.apply(enabled: settings.launchAtLogin, programPath: exePath)
```

- [ ] **Step 7: Build + manual verification**

Run: `cd tracker/app/ClaudeUsageBar && swift build`
Then flip the setting on (temporarily set `settings.launchAtLogin = true` via a debug build or `defaults write`), launch, and confirm `~/Library/LaunchAgents/com.claudeusagebar.agent.plist` exists with the correct program path. Turning it off removes the file.

- [ ] **Step 8: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBarCore/LaunchAgentPlist.swift tracker/app/ClaudeUsageBar/Tests/ClaudeUsageBarCoreTests/LaunchAgentPlistTests.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/LaunchAgentInstaller.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/AppDelegate.swift
git commit -m "feat: launch-at-login via LaunchAgent plist"
```

---

## Task 20: Settings UI + clock toggle wiring

**Files:**
- Modify: `Sources/ClaudeUsageBar/DropdownView.swift` (add settings controls)
- Modify: `Sources/ClaudeUsageBar/AppDelegate.swift` (react to settings changes)

> Adds a compact settings row to the popover: a 12h/24h toggle and a launch-at-login toggle. Changing the clock rebuilds the formatter and refreshes. Verification manual.

- [ ] **Step 1: Add a settings binding object**

In `Sources/ClaudeUsageBar/DropdownView.swift`, add at top (after imports):

```swift
final class SettingsBridge: ObservableObject {
    @Published var twelveHour: Bool
    @Published var launchAtLogin: Bool
    private let settings: Settings
    private let onChange: () -> Void

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.twelveHour = settings.clock == .twelveHour
        self.launchAtLogin = settings.launchAtLogin
    }

    func commit() {
        settings.clock = twelveHour ? .twelveHour : .twentyFourHour
        settings.launchAtLogin = launchAtLogin
        onChange()
    }
}
```

Add controls inside `DropdownView`'s footer area (after the Refresh/Quit `HStack`):

```swift
            Divider()
            HStack {
                Toggle("12-hour", isOn: $settings.twelveHour)
                    .toggleStyle(.checkbox).font(.system(size: 11.5))
                Spacer()
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.checkbox).font(.system(size: 11.5))
            }
            .onChange(of: settings.twelveHour) { _, _ in settings.commit() }
            .onChange(of: settings.launchAtLogin) { _, _ in settings.commit() }
```

Add the property to `DropdownView`:

```swift
    @ObservedObject var settings: SettingsBridge
```

- [ ] **Step 2: Construct and pass the bridge in AppDelegate**

In `applicationDidFinishLaunching(_:)`, before constructing `content`, add:

```swift
        let settingsBridge = SettingsBridge(settings: settings) { [weak self] in
            self?.reloadFormatterAndLaunchAgent()
        }
```

Add `settings: settingsBridge` to the `DropdownView(...)` initializer call.

Add the method:

```swift
    private func reloadFormatterAndLaunchAgent() {
        let exePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        LaunchAgentInstaller.apply(enabled: settings.launchAtLogin, programPath: exePath)
        refresh()
    }
```

> Note: the menu bar text formatter reads `settings.clock` at build time in `applicationDidFinishLaunching`. For the clock toggle to affect the menu bar immediately, rebuild the view model's formatter. To keep this task small, the clock change takes effect on next app launch for the *menu bar*; the *popover* `resetText` closure reads `settings.clock` live via a fresh formatter — change that closure to construct the formatter from `self.settings.clock` on each call:

In the `resetText` closure, replace the captured `formatterForView` with a live one:

```swift
            resetText: { [weak self] date in
                let clock = (self?.settings.clock) ?? .twentyFourHour
                return ResetFormatter(clock: clock, calendar: .current).string(for: date, now: Date())
            },
```

- [ ] **Step 3: Build + manual verification**

Run: `cd tracker/app/ClaudeUsageBar && swift build && swift run`
Expected: toggling **12-hour** changes the popover reset times to AM/PM form; toggling **Launch at login** creates/removes the LaunchAgent plist. Both persist across relaunches.

- [ ] **Step 4: Commit**

```bash
git add tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/DropdownView.swift tracker/app/ClaudeUsageBar/Sources/ClaudeUsageBar/AppDelegate.swift
git commit -m "feat: settings UI (12h/24h, launch at login)"
```

---

## Task 21: Package into a .app bundle

**Files:**
- Create: `tracker/app/package_app.sh`
- Create: `tracker/app/ClaudeUsageBar/Resources/Info.plist`

> Produces `ClaudeUsageBar.app` with `LSUIElement` so it runs as a menu bar accessory when double-clicked (not just via `swift run`). Verification manual.

- [ ] **Step 1: Create the Info.plist template**

Create `tracker/app/ClaudeUsageBar/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClaudeUsageBar</string>
    <key>CFBundleIdentifier</key><string>com.claudeusagebar.app</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>ClaudeUsageBar</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Create the packaging script**

Create `tracker/app/package_app.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/ClaudeUsageBar"
swift build -c release
APP="../ClaudeUsageBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ClaudeUsageBar" "$APP/Contents/MacOS/ClaudeUsageBar"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
echo "Built $APP"
```

- [ ] **Step 3: Build + manual verification**

Run:
```bash
chmod +x tracker/app/package_app.sh
tracker/app/package_app.sh
open tracker/app/ClaudeUsageBar.app
```
Expected: the app launches as a menu bar item with no Dock icon, reads the cache file, and shows the dropdown on click.

- [ ] **Step 4: Commit**

```bash
git add tracker/app/package_app.sh tracker/app/ClaudeUsageBar/Resources/Info.plist
git commit -m "feat: package ClaudeUsageBar as a .app bundle"
```

---

## Task 22: Full test sweep + README

**Files:**
- Create: `tracker/app/ClaudeUsageBar/README.md`

- [ ] **Step 1: Run the entire core test suite**

Run: `cd tracker/app/ClaudeUsageBar && swift test`
Expected: ALL tests PASS (CacheSchema, UsageModel, ResetFormatter, UsageLevel, SnapshotEvaluator, MonotonicSnapshotGate, MenuBarTextBuilder, CacheFileReader, Settings, UsageViewModel, OAuthRefreshClient, LaunchAgentPlist, Smoke).

- [ ] **Step 2: Run the producer test suite**

Run: `python3 -m unittest discover -s tracker/producer/tests -v`
Expected: ALL PASS.

- [ ] **Step 3: Write the README**

Create `tracker/app/ClaudeUsageBar/README.md` documenting: what the app does, the producer/consumer split, how to install (`package_app.sh`, the statusline edit + `refreshInterval`), the cache file location/schema, the manual Refresh limitation (429), and how to run tests. Keep it concise (under ~60 lines).

- [ ] **Step 4: Commit**

```bash
git add tracker/app/ClaudeUsageBar/README.md
git commit -m "docs: ClaudeUsageBar README"
```

---

## Self-Review Notes (for the planner)

- **Spec coverage:** producer/atomic-rename (Task 1), statusline wiring + refreshInterval (Task 2), schema (Task 4), domain model (Task 5), reset formatting 12h/24h same-day/weekday (Task 6), color thresholds (Task 7), stale + passed-reset (Task 8), monotonic guard (Task 9), menu bar format `42% →15:42  18% →Sun 16:00` (Task 10), reader last-good (Task 11), settings (Task 12, 20), view model + "updated Ns ago" + no-data text (Task 13), app shell + 10s timer (Task 14), file watcher (Task 15), minimal dropdown with bars/reset/refresh/quit (Task 16), manual 429-tolerant API refresh (Task 17–18), Keychain token (Task 18), launch-at-login (Task 19), settings UI (Task 20), .app packaging/LSUIElement (Task 21), test sweep + docs (Task 22). All spec §§1–13 requirements mapped.
- **Type consistency:** `UsageWindow`, `UsageSnapshot`, `DisplayWindow`, `EvaluatedSnapshot`, `RefreshOutcome`, `HTTPFetching`, `Settings`, `ResetFormatter.Clock`, `UsageViewModel.apply/note` names are consistent across all referencing tasks.
- **Deviations from spec (intentional, toolchain-driven):** AppKit `NSStatusItem`+`NSPopover` instead of SwiftUI `MenuBarExtra`; LaunchAgent plist instead of `SMAppService`; both documented in the header and preserve the spec's UX and behavior.
