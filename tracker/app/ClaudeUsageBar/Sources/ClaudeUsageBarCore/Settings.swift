import Foundation

public final class Settings {
    private let defaults: UserDefaults
    private enum Key {
        static let clock = "clock"
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var clock: ResetFormatter.Clock {
        get { defaults.string(forKey: Key.clock) == "12" ? .twelveHour : .twentyFourHour }
        set { defaults.set(newValue == .twelveHour ? "12" : "24", forKey: Key.clock) }
    }

    public var refreshInterval: Int {
        get {
            let v = defaults.integer(forKey: Key.refreshInterval)
            return v == 0 ? 10 : v
        }
        set { defaults.set(newValue, forKey: Key.refreshInterval) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }
}
