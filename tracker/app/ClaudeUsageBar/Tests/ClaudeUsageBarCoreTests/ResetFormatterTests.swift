import Testing
import Foundation
@testable import ClaudeUsageBarCore

private func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}
private let refNow = Date(timeIntervalSince1970: 1780057800) // 2026-05-29 12:30 UTC Fri

@Test func resetSameDay24h() {
    let f = ResetFormatter(clock: .twentyFourHour, calendar: utcCalendar())
    let reset = Date(timeIntervalSince1970: 1780069320) // 15:42 same day
    #expect(f.string(for: reset, now: refNow) == "15:42")
}

@Test func resetOtherDay24h() {
    let f = ResetFormatter(clock: .twentyFourHour, calendar: utcCalendar())
    let reset = Date(timeIntervalSince1970: 1780243200) // Sun 16:00
    #expect(f.string(for: reset, now: refNow) == "Sun 16:00")
}

@Test func resetSameDay12h() {
    let f = ResetFormatter(clock: .twelveHour, calendar: utcCalendar())
    let reset = Date(timeIntervalSince1970: 1780069320)
    #expect(f.string(for: reset, now: refNow) == "3:42 PM")
}

@Test func resetOtherDay12h() {
    let f = ResetFormatter(clock: .twelveHour, calendar: utcCalendar())
    let reset = Date(timeIntervalSince1970: 1780243200)
    #expect(f.string(for: reset, now: refNow) == "Sun 4:00 PM")
}
