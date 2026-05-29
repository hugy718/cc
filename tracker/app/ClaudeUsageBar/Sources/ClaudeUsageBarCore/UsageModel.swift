import Foundation

public struct UsageWindow: Equatable {
    public let usedPercentage: Double
    public let resetsAt: Date
    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable {
    public let capturedAt: Date
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?

    public init(capturedAt: Date, fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public init(file: UsageCacheFile) {
        self.capturedAt = Date(timeIntervalSince1970: file.capturedAt)
        self.fiveHour = UsageSnapshot.window(file.fiveHour)
        self.sevenDay = UsageSnapshot.window(file.sevenDay)
    }

    private static func window(_ dto: RateLimitWindowDTO?) -> UsageWindow? {
        guard let dto, let pct = dto.usedPercentage, let reset = dto.resetsAt else {
            return nil
        }
        return UsageWindow(usedPercentage: pct, resetsAt: Date(timeIntervalSince1970: reset))
    }
}
