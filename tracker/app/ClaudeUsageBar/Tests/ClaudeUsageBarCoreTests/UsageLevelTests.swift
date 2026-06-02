import Testing
@testable import ClaudeUsageBarCore

@Test func usageLevelThresholds() {
    #expect(UsageLevel(percentage: 0) == .low)
    #expect(UsageLevel(percentage: 49.9) == .low)
    #expect(UsageLevel(percentage: 50) == .medium)
    #expect(UsageLevel(percentage: 79.9) == .medium)
    #expect(UsageLevel(percentage: 80) == .high)
    #expect(UsageLevel(percentage: 100) == .high)
}
