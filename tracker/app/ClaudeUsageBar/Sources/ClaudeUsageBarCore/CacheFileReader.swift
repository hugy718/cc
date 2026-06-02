import Foundation

public final class CacheFileReader {
    private let url: URL
    private var lastGood: UsageSnapshot?

    public init(url: URL) {
        self.url = url
    }

    /// Reads and decodes the cache file. On missing/malformed file returns the
    /// last good snapshot (nil if none yet).
    public func read() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(UsageCacheFile.self, from: data)
        else { return lastGood }
        let snapshot = UsageSnapshot(file: file)
        lastGood = snapshot
        return snapshot
    }
}
