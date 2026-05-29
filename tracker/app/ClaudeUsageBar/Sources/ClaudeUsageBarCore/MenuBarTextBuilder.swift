import Foundation

public struct MenuBarSegment: Equatable {
    public let percentText: String   // e.g. "42%"
    public let resetText: String     // e.g. "→15:42"
    public let level: UsageLevel
}

public struct MenuBarTextBuilder {
    private let formatter: ResetFormatter

    public init(formatter: ResetFormatter) {
        self.formatter = formatter
    }

    public func segments(for snapshot: EvaluatedSnapshot, now: Date) -> [MenuBarSegment] {
        [snapshot.fiveHour, snapshot.sevenDay].compactMap { $0 }.map { w in
            MenuBarSegment(
                percentText: "\(Int(w.usedPercentage.rounded()))%",
                resetText: "→\(formatter.string(for: w.resetsAt, now: now))",
                level: UsageLevel(percentage: w.usedPercentage))
        }
    }

    public func text(for snapshot: EvaluatedSnapshot, now: Date) -> String {
        let segs = segments(for: snapshot, now: now)
        return segs.isEmpty ? "—" : segs.map { "\($0.percentText) \($0.resetText)" }.joined(separator: "  ")
    }
}
