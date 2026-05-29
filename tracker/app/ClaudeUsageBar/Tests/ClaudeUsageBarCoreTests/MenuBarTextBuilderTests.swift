import Testing
import Foundation
@testable import ClaudeUsageBarCore

private func mbCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}
private let mbNow = Date(timeIntervalSince1970: 1780057800) // 2026-05-29 12:30 UTC Fri

@Test func menuBarBothWindows24h() {
    let b = MenuBarTextBuilder(formatter: ResetFormatter(clock: .twentyFourHour, calendar: mbCalendar()))
    let e = EvaluatedSnapshot(
        capturedAt: mbNow,
        fiveHour: DisplayWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1780069320), isStale: false, didReset: false),
        sevenDay: DisplayWindow(usedPercentage: 18, resetsAt: Date(timeIntervalSince1970: 1780243200), isStale: false, didReset: false))
    #expect(b.text(for: e, now: mbNow) == "42% →15:42  18% →Sun 16:00")
}

@Test func menuBarMissingWindowShowsDash() {
    let b = MenuBarTextBuilder(formatter: ResetFormatter(clock: .twentyFourHour, calendar: mbCalendar()))
    let e = EvaluatedSnapshot(capturedAt: mbNow, fiveHour: nil, sevenDay: nil)
    #expect(b.text(for: e, now: mbNow) == "—")
}

@Test func menuBarRoundsPercentage() {
    let b = MenuBarTextBuilder(formatter: ResetFormatter(clock: .twentyFourHour, calendar: mbCalendar()))
    let e = EvaluatedSnapshot(
        capturedAt: mbNow,
        fiveHour: DisplayWindow(usedPercentage: 42.7, resetsAt: Date(timeIntervalSince1970: 1780069320), isStale: false, didReset: false),
        sevenDay: nil)
    #expect(b.text(for: e, now: mbNow) == "43% →15:42")
}
