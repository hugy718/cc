import Testing
import Foundation
@testable import ClaudeUsageBarCore

private func freshDefaults() -> UserDefaults {
    let suite = "ccu-tests-\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

@Test func settingsDefaults() {
    let s = Settings(defaults: freshDefaults())
    #expect(s.clock == .twentyFourHour)
    #expect(s.refreshInterval == 10)
    #expect(s.launchAtLogin == false)
}

@Test func settingsPersistsChanges() {
    let d = freshDefaults()
    let s = Settings(defaults: d)
    s.clock = .twelveHour
    s.refreshInterval = 30
    s.launchAtLogin = true
    let reloaded = Settings(defaults: d)
    #expect(reloaded.clock == .twelveHour)
    #expect(reloaded.refreshInterval == 30)
    #expect(reloaded.launchAtLogin == true)
}
