import Testing
import Foundation
@testable import ClaudeUsageBarCore

@Test func mapsBothWindows() {
    let file = UsageCacheFile(
        schema: 1, capturedAt: 1780040000,
        fiveHour: .init(usedPercentage: 42.0, resetsAt: 1780041720),
        sevenDay: .init(usedPercentage: 18.0, resetsAt: 1780300800))
    let snap = UsageSnapshot(file: file)
    #expect(snap.capturedAt == Date(timeIntervalSince1970: 1780040000))
    #expect(snap.fiveHour?.usedPercentage == 42.0)
    #expect(snap.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1780041720))
    #expect(snap.sevenDay?.usedPercentage == 18.0)
}

@Test func windowDroppedWhenFieldMissing() {
    let file = UsageCacheFile(
        schema: 1, capturedAt: 1,
        fiveHour: .init(usedPercentage: 42.0, resetsAt: nil),
        sevenDay: nil)
    let snap = UsageSnapshot(file: file)
    #expect(snap.fiveHour == nil)   // resets_at missing -> not a usable window
    #expect(snap.sevenDay == nil)
}

@Test func zeroPercentageWindowRetained() {
    let file = UsageCacheFile(
        schema: 1, capturedAt: 1,
        fiveHour: .init(usedPercentage: 0.0, resetsAt: 2),
        sevenDay: nil)
    let snap = UsageSnapshot(file: file)
    #expect(snap.fiveHour != nil)               // 0% is a real value, not "missing"
    #expect(snap.fiveHour?.usedPercentage == 0.0)
}
