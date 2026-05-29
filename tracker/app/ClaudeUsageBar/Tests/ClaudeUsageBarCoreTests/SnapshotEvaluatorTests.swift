import Testing
import Foundation
@testable import ClaudeUsageBarCore

private let evaluator = SnapshotEvaluator(staleAfter: 1800) // 30 min

@Test func freshWindowPassthrough() {
    let now = Date(timeIntervalSince1970: 1000)
    let snap = UsageSnapshot(
        capturedAt: Date(timeIntervalSince1970: 940), // 60s ago
        fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 5000)),
        sevenDay: nil)
    let e = evaluator.evaluate(snap, now: now)
    #expect(e.fiveHour?.usedPercentage == 42)
    #expect(e.fiveHour?.isStale == false)
    #expect(e.fiveHour?.didReset == false)
}

@Test func staleWhenOld() {
    let now = Date(timeIntervalSince1970: 5000)
    let snap = UsageSnapshot(
        capturedAt: Date(timeIntervalSince1970: 1000), // 4000s ago > 1800
        fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 9000)),
        sevenDay: nil)
    let e = evaluator.evaluate(snap, now: now)
    #expect(e.fiveHour?.isStale == true)
}

@Test func passedResetZeroesPercentage() {
    let now = Date(timeIntervalSince1970: 5000)
    let snap = UsageSnapshot(
        capturedAt: Date(timeIntervalSince1970: 4990),
        fiveHour: UsageWindow(usedPercentage: 42, resetsAt: Date(timeIntervalSince1970: 4000)), // past
        sevenDay: nil)
    let e = evaluator.evaluate(snap, now: now)
    #expect(e.fiveHour?.usedPercentage == 0)
    #expect(e.fiveHour?.didReset == true)
}
