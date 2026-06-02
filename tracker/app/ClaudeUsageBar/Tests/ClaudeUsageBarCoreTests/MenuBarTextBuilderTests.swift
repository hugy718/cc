import Testing
import Foundation
@testable import ClaudeUsageBarCore

private let mbNow = Date(timeIntervalSince1970: 1780057800) // 2026-05-29 12:30 UTC Fri

@Test func menuBarBothWindowsShowsPercentagesOnly() {
    let b = MenuBarTextBuilder()
    let e = EvaluatedSnapshot(
        capturedAt: mbNow,
        fiveHour: DisplayWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1780069320), isStale: false, didReset: false),
        sevenDay: DisplayWindow(usedPercentage: 18, resetsAt: Date(timeIntervalSince1970: 1780243200), isStale: false, didReset: false))
    // Compact menu bar: percentages only. Reset times live in the dropdown so the
    // status item stays narrow enough to survive the notch on built-in displays.
    #expect(b.text(for: e) == "42%  18%")
}

@Test func menuBarMissingWindowShowsDash() {
    let b = MenuBarTextBuilder()
    let e = EvaluatedSnapshot(capturedAt: mbNow, fiveHour: nil, sevenDay: nil)
    #expect(b.text(for: e) == "—")
}

@Test func menuBarRoundsPercentage() {
    let b = MenuBarTextBuilder()
    let e = EvaluatedSnapshot(
        capturedAt: mbNow,
        fiveHour: DisplayWindow(usedPercentage: 42.7, resetsAt: Date(timeIntervalSince1970: 1780069320), isStale: false, didReset: false),
        sevenDay: nil)
    #expect(b.text(for: e) == "43%")
}

@Test func menuBarSegmentsCarryLevels() {
    let b = MenuBarTextBuilder()
    let e = EvaluatedSnapshot(
        capturedAt: mbNow,
        fiveHour: DisplayWindow(usedPercentage: 85, resetsAt: Date(timeIntervalSince1970: 1780069320), isStale: false, didReset: false),
        sevenDay: DisplayWindow(usedPercentage: 18, resetsAt: Date(timeIntervalSince1970: 1780243200), isStale: false, didReset: false))
    let segs = b.segments(for: e)
    #expect(segs.count == 2)
    #expect(segs[0].percentText == "85%")
    #expect(segs[0].level == .high)
    #expect(segs[1].level == .low)
}
