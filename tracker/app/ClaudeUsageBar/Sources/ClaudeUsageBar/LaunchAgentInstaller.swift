import Foundation
import ClaudeUsageBarCore

enum LaunchAgentInstaller {
    static let label = "com.claudeusagebar.agent"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func apply(enabled: Bool, programPath: String) {
        if enabled {
            let xml = LaunchAgentPlist.xml(label: label, programPath: programPath)
            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? xml.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
