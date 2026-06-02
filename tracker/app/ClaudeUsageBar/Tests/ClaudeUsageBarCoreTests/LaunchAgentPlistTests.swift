import Testing
@testable import ClaudeUsageBarCore

@Test func launchAgentPlistContainsLabelAndProgram() {
    let xml = LaunchAgentPlist.xml(label: "com.claudeusagebar.agent",
                                   programPath: "/Applications/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar")
    #expect(xml.contains("<key>Label</key>"))
    #expect(xml.contains("<string>com.claudeusagebar.agent</string>"))
    #expect(xml.contains("/Applications/ClaudeUsageBar.app/Contents/MacOS/ClaudeUsageBar"))
    #expect(xml.contains("<key>RunAtLoad</key>"))
    #expect(xml.hasPrefix("<?xml"))
}
