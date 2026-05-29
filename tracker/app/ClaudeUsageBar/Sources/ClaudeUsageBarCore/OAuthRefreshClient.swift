import Foundation

public protocol HTTPFetching: Sendable {
    func get(url: URL, bearer: String) async throws -> (Data, Int)
}

public enum RefreshOutcome: Equatable, Sendable {
    case success(UsageSnapshot)
    case rateLimited
    case failed(status: Int)
}


public struct OAuthRefreshClient: Sendable {
    private let fetcher: any HTTPFetching
    private let url: URL

    public init(fetcher: any HTTPFetching, url: URL) {
        self.fetcher = fetcher
        self.url = url
    }

    public func refresh(token: String) async throws -> RefreshOutcome {
        let (data, status) = try await fetcher.get(url: url, bearer: token)
        if status == 429 { return .rateLimited }
        guard status == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(4000) ?? ""
            CCULog.write("API status \(status) body: \(snippet)")
            return .failed(status: status)
        }
        // The live response uses the same window field names as the cache file.
        struct Body: Decodable {
            let five_hour: RateLimitWindowDTO?
            let seven_day: RateLimitWindowDTO?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(4000) ?? ""
            CCULog.write("API 200 but unexpected body shape: \(snippet)")
            return .failed(status: 200)
        }
        let file = UsageCacheFile(schema: 1, capturedAt: Date().timeIntervalSince1970,
                                  fiveHour: body.five_hour, sevenDay: body.seven_day)
        return .success(UsageSnapshot(file: file))
    }
}
