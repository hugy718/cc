import Combine
import ClaudeUsageBarCore

@MainActor
final class SettingsBridge: ObservableObject {
    @Published var twelveHour: Bool
    @Published var launchAtLogin: Bool
    private let settings: Settings
    private let onChange: () -> Void

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        self.twelveHour = settings.clock == .twelveHour
        self.launchAtLogin = settings.launchAtLogin
    }

    func setTwelveHour(_ v: Bool) {
        twelveHour = v
        settings.clock = v ? .twelveHour : .twentyFourHour
        onChange()
    }

    func setLaunchAtLogin(_ v: Bool) {
        launchAtLogin = v
        settings.launchAtLogin = v
        onChange()
    }
}
