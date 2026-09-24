import Foundation
import Testing
import NutritionCore
@testable import Tarelka

@MainActor
struct MenuBarTests {
    @Test func repeatingRecentMealCreatesNewTodayEntryWithSamePortion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Meal(date: Date().addingTimeInterval(-86400), kind: .dinner,
                            name: "Каша", weight: 150,
                            ingredients: [Ingredient(name: "Крупа", grams: 150,
                                                     per100: Nutrients(calories: 120, protein: 4, fat: 2, carbs: 20))])
        try MealRepository(directory: directory).save([original])
        let model = AppModel(directory: directory)
        model.repeatMeal(original)
        #expect(model.meals.count == 2)
        #expect(model.meals(on: Date()).count == 1)
        #expect(model.meals[0].id != original.id)
        #expect(model.meals[0].ingredients == original.ingredients)
        #expect(try MealRepository(directory: directory).load().count == 2)
    }
}
