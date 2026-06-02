import Foundation

public struct MenuBarSegment: Equatable {
    public let percentText: String   // e.g. "42%"
    public let level: UsageLevel
}

public struct MenuBarTextBuilder {
    public init() {}

    public func segments(for snapshot: EvaluatedSnapshot) -> [MenuBarSegment] {
        [snapshot.fiveHour, snapshot.sevenDay].compactMap { $0 }.map { w in
            MenuBarSegment(
                percentText: "\(Int(w.usedPercentage.rounded()))%",
                level: UsageLevel(percentage: w.usedPercentage))
        }
    }

    /// Compact menu-bar string: percentages only, e.g. "42%  18%".
    /// Reset times are shown in the dropdown instead, keeping the status item
    /// narrow enough to survive the notch on a built-in display.
    public func text(for snapshot: EvaluatedSnapshot) -> String {
        let segs = segments(for: snapshot)
        return segs.isEmpty ? "—" : segs.map { $0.percentText }.joined(separator: "  ")
    }
}
