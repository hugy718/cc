import Foundation
import Combine

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public private(set) var menuBarText: String = "—"
    @Published public private(set) var evaluated: EvaluatedSnapshot?
    @Published public private(set) var updatedAgoText: String = ""
    @Published public private(set) var noteText: String?

    private let evaluator: SnapshotEvaluator
    private let textBuilder = MenuBarTextBuilder()

    public init(evaluator: SnapshotEvaluator) {
        self.evaluator = evaluator
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
        menuBarText = textBuilder.text(for: e)
        updatedAgoText = "updated " + Self.ago(from: e.capturedAt, to: now)
        noteText = nil
    }

    nonisolated static func ago(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        if s < 60 { return "\(s)s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        return "\(m / 60)h ago"
    }
}
