import Testing
import Foundation
@testable import ClaudeUsageBarCore

private func vmCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}
private let vmNow = Date(timeIntervalSince1970: 1780057800) // 2026-05-29 12:30 UTC

@MainActor @Test func vmRefreshProducesMenuBarText() {
    let vm = UsageViewModel(
        formatter: ResetFormatter(clock: .twentyFourHour, calendar: vmCalendar()),
        evaluator: SnapshotEvaluator(staleAfter: 1800))
    let snap = UsageSnapshot(
        capturedAt: Date(timeIntervalSince1970: 1780057740), // 60s ago
        fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 1780069320)),
        sevenDay: UsageWindow(usedPercentage: 18, resetsAt: Date(timeIntervalSince1970: 1780243200)))
    vm.apply(snapshot: snap, now: vmNow)
    #expect(vm.menuBarText == "42% →15:42  18% →Sun 16:00")
    #expect(vm.updatedAgoText == "updated 1m ago")
}

@MainActor @Test func vmNoDataText() {
    let vm = UsageViewModel(
        formatter: ResetFormatter(clock: .twentyFourHour, calendar: vmCalendar()),
        evaluator: SnapshotEvaluator(staleAfter: 1800))
    vm.apply(snapshot: nil, now: vmNow)
    #expect(vm.menuBarText == "—")
    #expect(vm.evaluated == nil)
}

@MainActor @Test func vmNoteSetsText() {
    let vm = UsageViewModel(
        formatter: ResetFormatter(clock: .twentyFourHour, calendar: vmCalendar()),
        evaluator: SnapshotEvaluator(staleAfter: 1800))
    vm.note("Rate-limited, try later")
    #expect(vm.noteText == "Rate-limited, try later")
}

@MainActor @Test func vmApplyClearsNote() {
    let vm = UsageViewModel(
        formatter: ResetFormatter(clock: .twentyFourHour, calendar: vmCalendar()),
        evaluator: SnapshotEvaluator(staleAfter: 1800))
    vm.note("Rate-limited, try later")
    let snap = UsageSnapshot(capturedAt: vmNow,
        fiveHour: UsageWindow(usedPercentage: 10, resetsAt: Date(timeIntervalSince1970: 1780069320)),
        sevenDay: nil)
    vm.apply(snapshot: snap, now: vmNow)
    #expect(vm.noteText == nil)
}
