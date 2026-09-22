import Foundation
import Testing
@testable import NutritionCore

struct MacroTargetsTests {
    private let date = Date(timeIntervalSince1970: 1_788_865_200)
    private var personal: PersonalData {
        var data = PersonalData()
        data.profile = CalorieProfile(height: 180, weight: 80, age: 30, sex: .male, activity: .high)
        return data
    }

    @Test func planningSplitPreservesEnergyAndRejectsInvalidBudgets() throws {
        for calories in [500.0, 1649, 2000, 2380, 10_000] {
            let targets = try #require(MacroTargets(calories: calories))
            #expect(abs(targets.protein * 4 + targets.fat * 9 + targets.carbs * 4 - calories) < 0.000001)
        }
        let targets = try #require(MacroTargets(calories: 2000))
        #expect(targets.protein == 100)
        #expect(abs(targets.fat - 200.0 / 3) < 0.000001)
        #expect(targets.carbs == 250)
        for invalid in [0.0, -1, .nan, .infinity] { #expect(MacroTargets(calories: invalid) == nil) }
    }

    @Test func profileChangesRecalculateTargetsAndEatingOnlyChangesProgress() throws {
        var data = personal
        let initial = try #require(data.budget(on: date, eaten: 0)?.macroTargets)
        #expect(initial.protein == 89) // 1780 kcal, resting expenditure.
        #expect(data.budget(on: date, eaten: 800)?.macroTargets == initial)
        data.profile?.weight = 90
        #expect(data.budget(on: date, eaten: 0)?.macroTargets?.protein == 94)
        data.profile?.height = 196
        #expect(data.budget(on: date, eaten: 0)?.macroTargets?.protein == 99)
    }

    @Test func activityReplacementDeficitAndDateUseTheSameEnergyBudget() throws {
        var data = personal
        data.budgetSettings = BudgetSettings(accounting: .watch, goal: .gentleLoss)
        try data.mergeActivity([DailyActivity(day: DayKey.string(date), activeCalories: 600, updatedAt: date, source: .manual)])
        let budget = try #require(data.budget(on: date, eaten: 500))
        #expect(budget.target == 2142) // 1780 + 600 − 238.
        #expect(budget.macroTargets == MacroTargets(calories: 2142))
        try data.mergeActivity([DailyActivity(day: DayKey.string(date), activeCalories: 300, updatedAt: date.addingTimeInterval(1), source: .manual)])
        #expect(data.budget(on: date, eaten: 500)?.macroTargets == MacroTargets(calories: 1872))
        let nextDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: date))
        #expect(data.budget(on: nextDay, eaten: 0)?.macroTargets == MacroTargets(calories: 1602))
        #expect(data.budget(on: nextDay, eaten: 0)?.awaitingActivity == true)
    }

    @Test func estimatedActivityAndManualBudgetDoNotDoubleCount() throws {
        var data = personal
        data.budgetSettings = BudgetSettings(accounting: .estimated, goal: .maintain)
        data.activity = [DailyActivity(day: DayKey.string(date), activeCalories: 600, updatedAt: date, source: .manual)]
        #expect(data.budget(on: date, eaten: 0)?.macroTargets == MacroTargets(calories: 3071))
        data.manualTarget = 2000
        data.budgetSettings?.goal = .gentleLoss
        #expect(data.budget(on: date, eaten: 0)?.macroTargets == MacroTargets(calories: 2000))
        data.budgetSettings?.accounting = .watch
        #expect(data.budget(on: date, eaten: 0)?.macroTargets == MacroTargets(calories: 2600))
    }

    @Test func progressKeepsExcessSeparateFromRemainingAndClampsBar() {
        let below = MacroProgress(eaten: 30, target: 100)
        #expect(below.remaining == 70 && below.excess == 0 && below.fraction == 0.3)
        let above = MacroProgress(eaten: 120, target: 100)
        #expect(above.remaining == 0 && above.excess == 20 && above.fraction == 1)
        let exact = MacroProgress(eaten: 100, target: 100)
        #expect(exact.remaining == 0 && exact.excess == 0 && exact.fraction == 1)
        #expect(MacroProgress(eaten: 0, target: 0).fraction == 0)
    }

    @Test func coachReceivesSameTargetsAndTotalsIncludingDrinks() throws {
        let drink = Meal(date: date, kind: .snack, name: "Молоко", weight: 200,
                         ingredients: [Ingredient(name: "Молоко", amount: 200, unit: .milliliters,
                                                  per100: Nutrients(calories: 60, protein: 3, fat: 3, carbs: 5))])
        let context = CoachContext(date: date, meals: [drink], personal: personal)
        #expect(context.macroTargets == personal.budget(on: date, eaten: 120)?.macroTargets)
        #expect(context.eaten.protein == 6 && context.eaten.fat == 6 && context.eaten.carbs == 10)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
        let targets = try #require(json["macroTargets"] as? [String: Double])
        #expect(targets["protein"] == 89)
        let missing = CoachContext(date: date, meals: [drink], personal: PersonalData())
        #expect(missing.macroTargets == nil)
        #expect(missing.eaten == context.eaten)
    }

    @Test func oldProfileLoadsWithoutMigrationAndProducesTargets() throws {
        let old = Data(#"{"version":1,"products":[],"activity":[],"profile":{"height":180,"weight":80,"age":30,"sex":"Мужской","activity":"Мало движения"}}"#.utf8)
        let data = try JSONDecoder().decode(PersonalData.self, from: old)
        #expect(data.budget(on: date, eaten: 0)?.macroTargets == MacroTargets(calories: 1780))
        #expect(try JSONDecoder().decode(PersonalData.self, from: JSONEncoder().encode(data)) == data)
    }
}
