import Foundation
import Testing
import NutritionCore
@testable import Tarelka

@MainActor
struct AuditFollowupAppTests {
    private func withModel(_ test: (AppModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(AppModel(directory: directory), directory)
    }
    private func draft(_ name: String, _ grams: Double, calories: Double) -> IngredientDraft {
        IngredientDraft(Ingredient(name: name, grams: grams, per100: Nutrients(calories: calories)))
    }

    @Test func typingAPortionWeightKeepsOriginalProportions() throws {
        try withModel { model, _ in
            var rice = draft("Рис", 293.3, calories: 130)
            rice.needsCatalogReview = true; rice.lookupQuery = "rice cooked"
            model.drafts = [rice, draft("Масло", 6.7, calories: 899)]
            model.weight = "300"; model.hasResult = true; model.weightMode = .portion
            // Keystrokes on the way to 150 g: 1 → 15 → 150.
            for typed in ["1", "15", "150"] { model.weight = typed; model.rescale() }
            // Scaling from the rounded 1 g step would give 146,7 + 3,3.
            #expect(model.drafts.map(\.grams) == ["146,65", "3,35"])
            #expect(model.drafts[0].needsCatalogReview)
            #expect(model.drafts[0].lookupQuery == "rice cooked")
            // A manual weight edit starts a new basis.
            model.drafts[1].grams = "5"; model.weight = "151,65"; model.rescale()
            #expect(model.drafts.map(\.grams) == ["146,65", "5"])
        }
    }

    @Test func staleProductPickDoesNotResurrectADeletedRow() throws {
        try withModel { model, _ in
            let kept = draft("Сыр", 40, calories: 350), removed = draft("Хлеб", 60, calories: 250)
            model.drafts = [kept, removed]
            model.drafts.removeAll { $0.id == removed.id }
            model.addProduct(SavedProduct(name: "Творог", per100: Nutrients(calories: 90)), grams: 60, replacing: removed.id)
            #expect(model.drafts.map(\.name) == ["Сыр"])
        }
    }

    @Test func macroDerivedCaloriesAreRememberedForSavedProducts() throws {
        try withModel { model, _ in
            model.addProduct(SavedProduct(name: "Батончик", per100: Nutrients(calories: 400, protein: 10, fat: 20, carbs: 45),
                                          caloriesFromMacros: true), grams: 50)
            #expect(model.drafts[0].caloriesFromMacros)
            model.drafts[0].calories = "410"
            #expect(!model.drafts[0].caloriesFromMacros)
        }
    }

    @Test func repeatFromMenuBarCanBeUndone() throws {
        try withModel { model, directory in
            let original = Meal(date: Date().addingTimeInterval(-86400), kind: .dinner, name: "Каша", weight: 150,
                                ingredients: [Ingredient(name: "Крупа", grams: 150, per100: Nutrients(calories: 120))])
            try MealRepository(directory: directory).save([original])
            model.meals = try MealRepository(directory: directory).load()
            model.repeatMeal(original)
            #expect(model.lastRepeated != nil && model.meals.count == 2)
            model.undoRepeat()
            #expect(model.lastRepeated == nil)
            #expect(model.meals.map(\.id) == [original.id])
            #expect(try MealRepository(directory: directory).load().map(\.id) == [original.id])
        }
    }

    @Test func mealsCannotBeSavedOnAFutureDay() throws {
        try withModel { model, _ in
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let drink = Meal(date: tomorrow, kind: .snack, name: "Кефир", weight: 250,
                             ingredients: [Ingredient(name: "Кефир", amount: 250, unit: .milliliters,
                                                      per100: Nutrients(calories: 50, protein: 3, fat: 2, carbs: 4))])
            #expect(throws: DateError.self) { try model.saveDrink(drink) }
            model.startManual()
            model.dishName = "Суп"; model.drafts = [draft("Суп", 200, calories: 40)]
            model.mealDate = tomorrow
            model.saveMeal()
            #expect(model.meals.isEmpty)
            #expect(model.errorMessage == DateError.future.localizedDescription)
        }
    }

    @Test func openAIProviderWithoutKeyExplainsWhatToDo() throws {
        try withModel { model, _ in
            model.provider = .local
            let key = try model.recognitionKey()
            #expect(key == nil)
        }
    }
}
