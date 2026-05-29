import Foundation

public struct MenuBarTextBuilder {
    private let formatter: ResetFormatter

    public init(formatter: ResetFormatter) {
        self.formatter = formatter
    }

    public func text(for snapshot: EvaluatedSnapshot, now: Date) -> String {
        let parts = [snapshot.fiveHour, snapshot.sevenDay]
            .compactMap { $0 }
            .map { segment(for: $0, now: now) }
        return parts.isEmpty ? "—" : parts.joined(separator: "  ")
    }

    private func segment(for w: DisplayWindow, now: Date) -> String {
        let pct = Int(w.usedPercentage.rounded())
        let reset = formatter.string(for: w.resetsAt, now: now)
        return "\(pct)% →\(reset)"
    }
}
