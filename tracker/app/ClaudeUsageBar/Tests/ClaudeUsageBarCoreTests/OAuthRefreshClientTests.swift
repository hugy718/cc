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
    let body = #"{"five_hour":{"used_percentage":55.0,"resets_at":1780069320},"seven_day":{"used_percentage":12.0,"resets_at":1780243200}}"#
    let client = OAuthRefreshClient(fetcher: StubFetcher(statusCode: 200, bodyData: Data(body.utf8)),
                                    url: URL(string: "https://example.com")!)
    let outcome = try await client.refresh(token: "tok")
    guard case .success(let snap) = outcome else {
        Issue.record("expected success, got \(outcome)"); return
    }
    #expect(snap.fiveHour?.usedPercentage == 55.0)
}

@Test func refreshRateLimited() async throws {
    let client = OAuthRefreshClient(fetcher: StubFetcher(statusCode: 429, bodyData: Data()),
                                    url: URL(string: "https://example.com")!)
    let outcome = try await client.refresh(token: "tok")
    #expect(outcome == .rateLimited)
}
