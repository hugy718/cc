import Foundation

/// Lightweight append-only diagnostic log at ~/Library/Logs/ClaudeUsageBar.log
/// (also echoed to stderr). Used for troubleshooting the manual API refresh.
public enum CCULog {
    public static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClaudeUsageBar.log")

    public static func write(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)   // file did not exist yet
        }
        FileHandle.standardError.write(data)
    }
}
