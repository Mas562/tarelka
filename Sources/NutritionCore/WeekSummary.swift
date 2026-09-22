import Foundation

public struct WeekDaySummary: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let total: Nutrients
    public let entryCount: Int
    public let drinkCount: Int
    public let drinkMilliliters: Double
    public let estimated: Bool
    public let isFuture: Bool
    public let activeCalories: Double?
    public let budget: DayBudget?
    public var hasEntries: Bool { entryCount > 0 && !isFuture }
}

/// Calendar weeks start on Monday. Missing days are not zero-calorie observations.
public struct WeekSummary: Sendable {
    public let start: Date
    public let end: Date // Exclusive, next Monday.
    public let days: [WeekDaySummary]
    public var loggedDays: [WeekDaySummary] { days.filter(\.hasEntries) }
    public var elapsedDays: Int { days.filter { !$0.isFuture }.count }
    public var total: Nutrients { loggedDays.reduce(Nutrients()) { $0 + $1.total } }
    public var average: Nutrients? { loggedDays.isEmpty ? nil : total.scaled(by: 1 / Double(loggedDays.count)) }
    public var entryCount: Int { loggedDays.reduce(0) { $0 + $1.entryCount } }
    public var drinkCount: Int { loggedDays.reduce(0) { $0 + $1.drinkCount } }
    public var activityDays: [WeekDaySummary] { days.filter { !$0.isFuture && $0.activeCalories != nil } }
    public var totalActivity: Double? { activityDays.isEmpty ? nil : activityDays.reduce(0) { $0 + ($1.activeCalories ?? 0) } }

    public init(containing date: Date, now: Date = Date(), meals: [Meal], personal: PersonalData, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: day)!
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        self.start = start; self.end = end
        let today = calendar.startOfDay(for: now)
        let weekMeals = Dictionary(grouping: meals.filter { $0.date >= start && $0.date < end }) { calendar.startOfDay(for: $0.date) }
        days = (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            let future = date > today
            let entries = future ? [] : (weekMeals[date] ?? [])
            let total = entries.reduce(Nutrients()) { $0 + $1.total }
            let drinks = entries.filter(\.isDrink)
            let key = DayKey.string(date, timeZone: calendar.timeZone)
            let active = future ? nil : personal.activity.first { $0.day == key }?.activeCalories
            return WeekDaySummary(date: date, total: total, entryCount: entries.count, drinkCount: drinks.count,
                                  drinkMilliliters: drinks.reduce(0) { $0 + $1.weight }, estimated: entries.contains(where: \.isEstimate),
                                  isFuture: future, activeCalories: active,
                                  budget: future ? nil : personal.budget(on: date, eaten: total.calories, timeZone: calendar.timeZone))
        }
    }
}
