import Foundation
import Testing
@testable import NutritionCore

struct PersonalTests {
    @Test func weighedIngredientsUseTheirOwnLabels() throws {
        let sausage = SavedProduct(name: "Сосиска", per100: Nutrients(calories: 260, protein: 12, fat: 22, carbs: 3))
        let cheese = SavedProduct(name: "Сыр", per100: Nutrients(calories: 350, protein: 25, fat: 27, carbs: 0))
        let ingredients = [sausage.portion(grams: 70), cheese.portion(grams: 40)]
        let total = NutritionMath.total(ingredients)
        try NutritionMath.validate(ingredients, weight: 110)
        #expect(abs(total.calories - 322) < 0.001)
        #expect(abs(total.protein - 18.4) < 0.001)
        #expect(abs(total.fat - 26.2) < 0.001)
        #expect(abs(total.carbs - 2.1) < 0.001)
    }
    @Test func restingFormulaAndEstimatedModeRemainAvailable() throws {
        let male = CalorieProfile(height: 180, weight: 80, age: 30, sex: .male, activity: .low)
        let female = CalorieProfile(height: 165, weight: 60, age: 30, sex: .female, activity: .moderate)
        #expect(male.restingCalories == 1780)
        #expect(male.maintenanceCalories == 2136)
        #expect(female.restingCalories == 1320.25)
        #expect(female.maintenanceCalories == 2046)
        var data = PersonalData(); data.profile = male
        try data.mergeActivity([DailyActivity(day: "2026-09-08", activeCalories: 600, updatedAt: Date(), source: .appleHealth)])
        #expect(data.dailyTarget == 1780)
        data.budgetSettings = BudgetSettings(accounting: .estimated)
        #expect(data.dailyTarget == 2136)
        #expect(DailyBudget.remaining(target: try #require(data.dailyTarget), eaten: 2300) == -164)
        data.manualTarget = 2000
        #expect(data.dailyTarget == 2000)
    }
    @Test func invalidProfilesAndProductsAreRejected() throws {
        for profile in [
            CalorieProfile(height: 170, weight: 60, age: 17, sex: .female, activity: .low),
            CalorieProfile(height: .nan, weight: 60, age: 30, sex: .female, activity: .low),
            CalorieProfile(height: 170, weight: -60, age: 30, sex: .female, activity: .low)
        ] { #expect(profile.maintenanceCalories == nil) }
        #expect(!SavedProduct(name: " ", per100: Nutrients()).isValid)
        #expect(!SavedProduct(name: "Сыр", per100: Nutrients(calories: 300, protein: 80, fat: 30)).isValid)
        var data = PersonalData(); data.manualTarget = .infinity
        #expect(throws: (any Error).self) { try data.validate() }
    }
    private func export(_ body: String, time: String = "2026-09-08 18:00:00 +0500") -> Data {
        Data("<?xml version=\"1.0\"?><HealthData><ExportDate value=\"\(time)\"/>\(body)</HealthData>".utf8)
    }
    private func summary(_ day: String = "2026-09-08", calories: String = "450", unit: String = "kcal") -> String {
        "<ActivitySummary dateComponents=\"\(day)\" activeEnergyBurned=\"\(calories)\" activeEnergyBurnedUnit=\"\(unit)\"/>"
    }
    @Test func healthImportUsesMoveSummaryWithoutOverlappingRecords() throws {
        let body = "<Record type=\"HKQuantityTypeIdentifierActiveEnergyBurned\" value=\"450\"/>"
            + "<Workout totalEnergyBurned=\"450\"/>" + summary() + summary()
            + summary("2026-09-07", calories: "418.4", unit: "kJ")
        let results = try HealthActivityImporter.readXML(export(body))
        #expect(results.count == 2)
        #expect(results[0].activeCalories == 450)
        #expect(abs(results[1].activeCalories - 100) < 0.001)
        #expect(results[0].source == .appleHealth)
        #expect(results[0].updatedAt == ISO8601DateFormatter().date(from: "2026-09-08T13:00:00Z"))
    }
    @Test func importRejectsBadDatesUnitsConflictsAndNonfiniteNumbers() throws {
        for body in [summary("2026-02-30"), summary(calories: "nan"), summary(calories: "-1"), summary(unit: "J"),
                     summary() + summary(calories: "460"), summary(calories: "999999")] {
            #expect(throws: (any Error).self) { try HealthActivityImporter.readXML(export(body)) }
        }
        #expect(throws: (any Error).self) { try HealthActivityImporter.readXML(export("<Record/>")) }
        #expect(throws: (any Error).self) { try HealthActivityImporter.readXML(export(summary(), time: "oops")) }
        #expect(throws: (any Error).self) { try HealthActivityImporter.readXML(Data("<broken>".utf8)) }
        #expect(throws: (any Error).self) { try HealthActivityImporter.readXML(Data("<notHealth>\(summary())</notHealth>".utf8)) }
    }
    @Test func reimportReplacesTotalsAndDoesNotOverwriteNewerData() throws {
        var data = PersonalData()
        let original = try HealthActivityImporter.readXML(export(summary()))
        try data.mergeActivity(original); try data.mergeActivity(original)
        #expect(data.activity.count == 1); #expect(data.activity[0].activeCalories == 450)
        let newer = try HealthActivityImporter.readXML(export(summary(calories: "600"), time: "2026-09-08 19:00:00 +0500"))
        try data.mergeActivity(newer); try data.mergeActivity(original)
        #expect(data.activity[0].activeCalories == 600)
        #expect(!data.activity.contains { $0.day == "2026-09-07" })
    }
    @Test func transferFileAndDateValidation() throws {
        let json = Data(#"{"version":1,"days":[{"date":"2026-09-08","active_kcal":512,"updated_at":"2026-09-08T18:15:00+05:00"}]}"#.utf8)
        let result = try HealthActivityImporter.readJSON(json)
        #expect(result.first?.activeCalories == 512)
        #expect(result.first?.source == .transferFile)
        for bad in [#"{"version":2,"days":[]}"#, #"{"version":1,"days":[{"date":"2026-09-08","active_kcal":-1,"updated_at":"2026-09-08T18:15:00+05:00"}]}"#] {
            #expect(throws: (any Error).self) { try HealthActivityImporter.readJSON(Data(bad.utf8)) }
        }
        #expect(DayKey.isValid("2024-02-29")); #expect(!DayKey.isValid("2025-02-29"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-07T23:30:00Z"))
        #expect(DayKey.string(date, timeZone: TimeZone(secondsFromGMT: 5 * 3600)!) == "2026-09-08")
    }
    @Test func personalDataPersistsSeparatelyFromExistingMealsAndProtectsCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let meals = MealRepository(directory: directory)
        let ingredient = Ingredient(name: "Сыр", grams: 40, per100: Nutrients(calories: 350, protein: 25, fat: 27))
        let meal = Meal(date: Date(), kind: .snack, name: "Сыр", weight: 40, ingredients: [ingredient])
        try meals.save([meal]); let mealBytes = try Data(contentsOf: meals.journalURL)
        let repository = PersonalRepository(directory: directory)
        var data = try repository.load()
        data.products = [SavedProduct(name: "Сыр", per100: ingredient.per100)]
        data.profile = CalorieProfile(height: 180, weight: 80, age: 30, sex: .male, activity: .low)
        try data.mergeActivity(HealthActivityImporter.readXML(export(summary())))
        try repository.save(data)
        #expect(try repository.load() == data)
        data.products[0].per100.calories = 400; try repository.save(data)
        #expect(try Data(contentsOf: meals.journalURL) == mealBytes)
        #expect(try meals.load().first?.total.calories == 140)
        let damaged = Data("broken personal data".utf8); try damaged.write(to: repository.url)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect(try Data(contentsOf: repository.url) == damaged)
    }
}
