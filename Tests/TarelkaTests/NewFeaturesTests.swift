import Foundation
import Testing
import NutritionCore
@testable import Tarelka

@MainActor
struct NewFeaturesTests {
    @Test func databaseModeDoesNotUseInventedMacrosAndPreservesWeights() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(directory: directory)
        let components = [Ingredient(name: "Курица жареная", grams: 70, per100: Nutrients(calories: 555)),
                          Ingredient(name: "Сыр с упаковки", grams: 40, per100: Nutrients(calories: 999))]
        _ = model.personal.saveProduct(SavedProduct(name: "Сыр с упаковки", per100: Nutrients(calories: 350, protein: 25, fat: 27, carbs: 1)))
        model.applyRecognizedComponents(components, queries: ["chicken fried", "cheese"], useCatalog: true)
        #expect(model.drafts[0].calories.isEmpty && model.drafts[0].ingredient == nil)
        #expect(model.drafts[0].grams == "70")
        #expect(model.drafts[1].calories == "350" && model.drafts[1].grams == "40")
        #expect(!model.allIngredientsValid)
        let choice = try #require(FoodCatalog.shared.search("chicken fried").first)
        let oldID = model.drafts[0].id
        model.applyCatalog(choice, grams: 70, replacing: oldID)
        #expect(model.allIngredientsValid)
        #expect(model.ingredients[0].per100 == choice.per100)
        #expect(model.ingredientWeight == 110)
        #expect(model.ingredients[0].source == choice.source)
        model.applyRecognizedComponents(components, queries: [], useCatalog: false)
        #expect(model.drafts[0].calories == "555")
    }
    @Test func manualEditsInvalidateSourceButWeightChangeKeepsIt() throws {
        let food = try #require(FoodCatalog.shared.search("рис").first)
        var draft = IngredientDraft(food.ingredient(grams: 100))
        #expect(draft.ingredient?.source != nil)
        draft.grams = "50"
        #expect(draft.ingredient?.source != nil)
        draft.calories = "1"
        #expect(draft.ingredient?.source == nil)
        draft = IngredientDraft(food.ingredient(grams: 100)); draft.name = "Другой продукт"
        #expect(draft.ingredient?.source == nil)
    }
    @Test func removedIngredientIsNotReintroducedByStaleCatalogSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: directory)
        let food = try #require(FoodCatalog.shared.foods.first)
        model.applyCatalog(food, grams: 100, replacing: UUID())
        #expect(model.drafts.isEmpty)
    }
}
