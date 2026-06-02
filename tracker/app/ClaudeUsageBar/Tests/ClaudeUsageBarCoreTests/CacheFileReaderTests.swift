import Testing
import Foundation
@testable import ClaudeUsageBarCore

private func tempCacheFile(_ contents: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ccu-\(UUID().uuidString).json")
    try? contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Test func readsValidFile() {
    let url = tempCacheFile(#"{"schema":1,"captured_at":1780040000,"five_hour":{"used_percentage":42.0,"resets_at":1780041720}}"#)
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = CacheFileReader(url: url)
    let snap = reader.read()
    #expect(snap?.fiveHour?.usedPercentage == 42.0)
}

@Test func missingFileReturnsNil() {
    let reader = CacheFileReader(url: URL(fileURLWithPath: "/no/such/file.json"))
    #expect(reader.read() == nil)
}

@Test func malformedKeepsLastGood() {
    let good = tempCacheFile(#"{"schema":1,"captured_at":1,"five_hour":{"used_percentage":5.0,"resets_at":2}}"#)
    defer { try? FileManager.default.removeItem(at: good) }
    let reader = CacheFileReader(url: good)
    _ = reader.read()                       // caches last good
    try? "garbage".write(to: good, atomically: true, encoding: .utf8)
    let snap = reader.read()
    #expect(snap?.fiveHour?.usedPercentage == 5.0) // last good retained
}
