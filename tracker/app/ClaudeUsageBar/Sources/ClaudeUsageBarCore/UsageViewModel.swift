import Foundation
import Combine

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public private(set) var menuBarText: String = "—"
    @Published public private(set) var evaluated: EvaluatedSnapshot?
    @Published public private(set) var updatedAgoText: String = ""
    @Published public private(set) var noteText: String?

    private let formatter: ResetFormatter
    private let evaluator: SnapshotEvaluator
    private let textBuilder: MenuBarTextBuilder

    public init(formatter: ResetFormatter, evaluator: SnapshotEvaluator) {
        self.formatter = formatter
        self.evaluator = evaluator
        self.textBuilder = MenuBarTextBuilder(formatter: formatter)
    }

    public func note(_ message: String) {
        noteText = message
    }

    public func apply(snapshot: UsageSnapshot?, now: Date) {
        guard let snapshot else {
            menuBarText = "—"
            evaluated = nil
            updatedAgoText = "No data yet"
            return
        }
        let e = evaluator.evaluate(snapshot, now: now)
        evaluated = e
        menuBarText = textBuilder.text(for: e, now: now)
        updatedAgoText = "updated " + Self.ago(from: e.capturedAt, to: now)
    }

    nonisolated static func ago(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        return "\(m / 60)h ago"
    }
}
