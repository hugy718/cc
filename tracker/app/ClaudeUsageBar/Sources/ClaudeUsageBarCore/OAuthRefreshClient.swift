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
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(4000) ?? ""
            CCULog.write("API 200 but unexpected body shape: \(snippet)")
            return .failed(status: 200)
        }
        let snapshot = UsageSnapshot(
            capturedAt: Date(),
            fiveHour: Self.window(body.five_hour),
            sevenDay: Self.window(body.seven_day))
        return .success(snapshot)
    }

    // The /api/oauth/usage response shape: each window is
    // {"utilization": <0-100 Double>, "resets_at": "<ISO-8601 string>"}.
    private struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }
    private struct Body: Decodable {
        let five_hour: Window?
        let seven_day: Window?
    }

    private static func window(_ w: Window?) -> UsageWindow? {
        guard let w, let pct = w.utilization, let date = parseISODate(w.resets_at) else { return nil }
        return UsageWindow(usedPercentage: pct, resetsAt: date)
    }

    /// Parse an ISO-8601 timestamp like "2026-05-29T16:20:00.696968+00:00".
    /// Fractional seconds (microsecond precision) are stripped first because
    /// ISO8601DateFormatter does not reliably accept >3 fractional digits.
    static func parseISODate(_ s: String?) -> Date? {
        guard var str = s else { return nil }
        if let dot = str.firstIndex(of: ".") {
            let after = str[str.index(after: dot)...]
            if let tz = after.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                str.removeSubrange(dot..<tz)
            } else {
                str.removeSubrange(dot..<str.endIndex)
            }
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: str)
    }
}
