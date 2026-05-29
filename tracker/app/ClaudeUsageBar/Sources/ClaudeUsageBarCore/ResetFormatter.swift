import Foundation

public struct ResetFormatter {
    public enum Clock { case twelveHour, twentyFourHour }

    private let clock: Clock
    private let calendar: Calendar

    public init(clock: Clock, calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    public func string(for resetDate: Date, now: Date) -> String {
        let sameDay = calendar.isDate(resetDate, inSameDayAs: now)
        let timePart: String
        switch clock {
        case .twentyFourHour: timePart = format(resetDate, "HH:mm")
        case .twelveHour:     timePart = format(resetDate, "h:mm a")
        }
        if sameDay { return timePart }
        return format(resetDate, "EEE") + " " + timePart
    }

    private func format(_ date: Date, _ template: String) -> String {
        let df = DateFormatter()
        df.calendar = calendar
        df.locale = calendar.locale ?? Locale(identifier: "en_US_POSIX")
        df.timeZone = calendar.timeZone
        df.dateFormat = template
        return df.string(from: date)
    }
}
