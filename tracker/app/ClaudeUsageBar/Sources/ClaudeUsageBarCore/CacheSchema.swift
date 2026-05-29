import Foundation

public struct RateLimitWindowDTO: Decodable, Equatable {
    public let usedPercentage: Double?
    public let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

public struct UsageCacheFile: Decodable, Equatable {
    public let schema: Int
    public let capturedAt: Double
    public let fiveHour: RateLimitWindowDTO?
    public let sevenDay: RateLimitWindowDTO?

    enum CodingKeys: String, CodingKey {
        case schema
        case capturedAt = "captured_at"
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
