import Testing
import Foundation
@testable import ClaudeUsageBarCore

private func gateSnap(_ t: TimeInterval) -> UsageSnapshot {
    UsageSnapshot(capturedAt: Date(timeIntervalSince1970: t), fiveHour: nil, sevenDay: nil)
}

@Test func gateAcceptsFirstAndNewer() {
    let gate = MonotonicSnapshotGate()
    #expect(gate.accept(gateSnap(100)) == true)
    #expect(gate.accept(gateSnap(200)) == true)
}

@Test func gateRejectsOlderOrEqual() {
    let gate = MonotonicSnapshotGate()
    #expect(gate.accept(gateSnap(200)) == true)
    #expect(gate.accept(gateSnap(150)) == false)
    #expect(gate.accept(gateSnap(200)) == false)
}
