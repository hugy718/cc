import Testing
import Foundation
@testable import ClaudeUsageBarCore

private struct StubFetcher: HTTPFetching {
    let statusCode: Int
    let bodyData: Data

    func get(url: URL, bearer: String) async throws -> (Data, Int) {
        return (bodyData, statusCode)
    }
}

@Test func refreshSuccessParsesSnapshot() async throws {
    // Real /api/oauth/usage shape: "utilization" (0-100) + ISO-8601 "resets_at"
    // (with microsecond fractional seconds that must be tolerated).
    let body = #"{"five_hour":{"utilization":55.0,"resets_at":"2026-05-29T16:20:00.696968+00:00"},"seven_day":{"utilization":12.0,"resets_at":"2026-06-02T05:00:00+00:00"},"seven_day_opus":null,"extra_usage":{"is_enabled":false}}"#
    let client = OAuthRefreshClient(fetcher: StubFetcher(statusCode: 200, bodyData: Data(body.utf8)),
                                    url: URL(string: "https://example.com")!)
    let outcome = try await client.refresh(token: "tok")
    guard case .success(let snap) = outcome else {
        Issue.record("expected success, got \(outcome)"); return
    }
    #expect(snap.fiveHour?.usedPercentage == 55.0)
    #expect(snap.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1780071600)) // 2026-05-29T16:20:00Z
    #expect(snap.sevenDay?.usedPercentage == 12.0)
}

@Test func refreshIgnoresWindowMissingFields() async throws {
    let body = #"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":{"utilization":7.0,"resets_at":"2026-06-02T05:00:00+00:00"}}"#
    let client = OAuthRefreshClient(fetcher: StubFetcher(statusCode: 200, bodyData: Data(body.utf8)),
                                    url: URL(string: "https://example.com")!)
    guard case .success(let snap) = try await client.refresh(token: "tok") else {
        Issue.record("expected success"); return
    }
    #expect(snap.fiveHour == nil)
    #expect(snap.sevenDay?.usedPercentage == 7.0)
}

@Test func refreshRateLimited() async throws {
    let client = OAuthRefreshClient(fetcher: StubFetcher(statusCode: 429, bodyData: Data()),
                                    url: URL(string: "https://example.com")!)
    let outcome = try await client.refresh(token: "tok")
    #expect(outcome == .rateLimited)
}
