import Foundation
import Testing
@testable import Tarelka

struct CalendarDatesTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return result
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    @Test func leapMonthGridIncludesEveryDayAndStartsOnMonday() {
        let days = CalendarDates.days(in: date(2024, 2, 19), calendar: calendar)
        #expect(days.count == 42)
        #expect(calendar.component(.weekday, from: days[0]) == 2)
        #expect(days.filter { calendar.component(.month, from: $0) == 2 }.count == 29)
        #expect(Set(days).count == 42)
    }
    @Test func gridCrossesYearAndDaylightSavingBoundaries() {
        let january = CalendarDates.days(in: date(2027, 1, 15), calendar: calendar)
        #expect(calendar.component(.year, from: january[0]) == 2026)
        let march = CalendarDates.days(in: date(2026, 3, 15), calendar: calendar)
        #expect(march.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        #expect(march.filter { calendar.component(.month, from: $0) == 3 }.count == 31)
    }
    @Test func todayIsAllowedRegardlessOfTimeButTomorrowIsNot() {
        let maximum = date(2026, 9, 21, 9)
        #expect(CalendarDates.isAllowed(date(2026, 9, 21, 23), through: maximum, calendar: calendar))
        #expect(!CalendarDates.isAllowed(date(2026, 9, 22, 0), through: maximum, calendar: calendar))
        #expect(CalendarDates.isAllowed(date(2027, 1, 1), through: nil, calendar: calendar))
    }
    @Test func changingMealDayPreservesLocalTimeAcrossDST() {
        let moved = CalendarDates.replacingDay(of: date(2026, 3, 28, 19, 45), with: date(2026, 3, 29), calendar: calendar)
        #expect(moved == date(2026, 3, 29, 19, 45))
    }
}
