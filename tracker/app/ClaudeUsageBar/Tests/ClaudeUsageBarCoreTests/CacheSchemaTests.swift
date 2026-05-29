import Testing
import Foundation
@testable import ClaudeUsageBarCore

private func decodeCacheFile(_ s: String) throws -> UsageCacheFile {
    try JSONDecoder().decode(UsageCacheFile.self, from: Data(s.utf8))
}

@Test func decodesFullFile() throws {
    let f = try decodeCacheFile(#"{"schema":1,"captured_at":1780040000,"five_hour":{"used_percentage":42.0,"resets_at":1780041720},"seven_day":{"used_percentage":18.0,"resets_at":1780300800}}"#)
    #expect(f.schema == 1)
    #expect(f.capturedAt == 1780040000)
    #expect(f.fiveHour?.usedPercentage == 42.0)
    #expect(f.fiveHour?.resetsAt == 1780041720)
    #expect(f.sevenDay?.usedPercentage == 18.0)
}

@Test func decodesWithMissingWindow() throws {
    let f = try decodeCacheFile(#"{"schema":1,"captured_at":1,"five_hour":{"used_percentage":5.0,"resets_at":2}}"#)
    #expect(f.sevenDay == nil)
    #expect(f.fiveHour?.usedPercentage == 5.0)
}

@Test func decodesWindowMissingFields() throws {
    let f = try decodeCacheFile(#"{"schema":1,"captured_at":1,"five_hour":{}}"#)
    #expect(f.fiveHour?.usedPercentage == nil)
    #expect(f.fiveHour?.resetsAt == nil)
}
