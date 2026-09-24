import Foundation
import Testing
@testable import NutritionCore

struct TodaySnapshotTests {
    @Test func widgetBalanceUsesSameActivityBudgetAndOnlyTodaysMeals() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let today = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
        let yesterday = ISO8601DateFormatter().date(from: "2026-09-23T12:00:00Z")!
        let food = Ingredient(name: "Еда", grams: 100,
                              per100: Nutrients(calories: 500, protein: 20, fat: 15, carbs: 60))
        let current = Meal(date: today, kind: .lunch, name: "Обед", weight: 100, ingredients: [food])
        let old = Meal(date: yesterday, kind: .lunch, name: "Вчера", weight: 100, ingredients: [food])
        var personal = PersonalData()
        personal.manualTarget = 2500
        personal.activity = [DailyActivity(day: "2026-09-24", activeCalories: 300,
                                           updatedAt: today, source: .manual)]
        let snapshot = TodaySnapshot(date: today, meals: [old, current], personal: personal, timeZone: zone)
        #expect(snapshot.entryCount == 1)
        #expect(snapshot.eaten.calories == 500)
        #expect(snapshot.target == 2800)
        #expect(snapshot.remaining == 2300)
        #expect(snapshot.activity == 300)
        #expect(snapshot.macroTargets?.protein == 140)
        #expect(try JSONDecoder().decode(TodaySnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test func widgetReadsCurrentDayFromJournalWithoutOpeningApp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let food = Ingredient(name: "Тест", grams: 100,
                              per100: Nutrients(calories: 400, protein: 10, fat: 12, carbs: 25))
        try MealRepository(directory: directory).save([
            Meal(date: day, kind: .lunch, name: "Обед", weight: 100, ingredients: [food])
        ])
        var profile = PersonalData()
        profile.manualTarget = 2000
        try PersonalRepository(directory: directory).save(profile)
        #expect(TodaySnapshotStore.load(on: day, directory: directory)?.remaining == 1600)
        #expect(TodaySnapshotStore.load(on: nextDay, directory: directory)?.remaining == 2000)
    }
}
