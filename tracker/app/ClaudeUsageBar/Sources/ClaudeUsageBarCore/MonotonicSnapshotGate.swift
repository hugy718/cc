import Foundation

public final class MonotonicSnapshotGate {
    private var last: Date?

    public init() {}

    /// Returns true and records the snapshot if it is strictly newer than the
    /// last accepted one; otherwise returns false and ignores it.
    public func accept(_ snapshot: UsageSnapshot) -> Bool {
        if let last, snapshot.capturedAt <= last { return false }
        last = snapshot.capturedAt
        return true
    }
}
