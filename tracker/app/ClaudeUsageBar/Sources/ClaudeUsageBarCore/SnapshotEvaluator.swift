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

public struct SnapshotEvaluator: Sendable {
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
