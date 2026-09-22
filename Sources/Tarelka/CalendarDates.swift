import Foundation

enum CalendarDates {
    static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    /// A stable six-week grid, starting on Monday, including neighbouring months.
    static func days(in month: Date, calendar: Calendar = .current) -> [Date] {
        let start = monthStart(month, calendar: calendar)
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: start) }
    }

    static func isAllowed(_ date: Date, through maximum: Date?, calendar: Calendar = .current) -> Bool {
        guard let maximum else { return true }
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: maximum)
    }

    /// Changing a meal's date must keep its local time, including across DST changes.
    static func replacingDay(of date: Date, with day: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: day) ?? day
    }
}
