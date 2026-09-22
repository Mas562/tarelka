import Foundation
import Testing
@testable import NutritionCore

struct FeatureRequestTests {
    @Test func catalogHasOfficialValuesAndRussianPreparationSearch() throws {
        let catalog = FoodCatalog.shared
        #expect(catalog.foods.count == 7793)
        #expect(Set(catalog.foods.map(\.id)).count == catalog.foods.count)
        #expect(catalog.foods.allSatisfy { $0.per100.isValidPer100 })
        let fried = catalog.search("курица жареная")
        #expect(!fried.isEmpty)
        #expect(fried.allSatisfy { $0.name.lowercased().contains("chicken") && $0.name.lowercased().contains("fried") })
        #expect(fried.first?.name == "Chicken, broilers or fryers, meat only, cooked, fried")
        #expect(!catalog.search("растительное масло", limit: 8000).contains { $0.name == "Egg, whole, cooked, hard-boiled" })
        #expect(FoodCatalog.localized("Chicken, meatless, breaded, fried").contains("без мяса"))
        let rice = try #require(catalog.foods.first { $0.name == "Rice, white, long-grain, regular, enriched, cooked" })
        #expect(rice.per100.calories == 130)
        #expect(rice.per100.protein == 2.69)
        #expect(rice.ingredient(grams: 200).total.calories == 260)
        #expect(catalog.exact("курица") == nil) // Ambiguity never silently picks a recipe.
        #expect(catalog.exact(rice.name)?.id == rice.id)
        #expect(catalog.search("совсемнесуществующийпродукт").isEmpty)
    }
    @Test func sourcesSurviveStorageAndSavedProductPortions() throws {
        let food = try #require(FoodCatalog.shared.search("рис").first)
        let ingredient = food.ingredient(grams: 70)
        let saved = try JSONDecoder().decode(Ingredient.self, from: JSONEncoder().encode(ingredient))
        #expect(saved.source == food.source)
        #expect(saved.grams == 70)
        let product = SavedProduct(name: food.displayName, per100: food.per100, source: food.source)
        #expect(product.portion(grams: 40).source == food.source)
        let legacy = Data(#"{"id":"C6B15D44-215B-4A77-9E4E-A9B5B2C72E21","name":"Сыр","per100":{"calories":300,"protein":20,"fat":20,"carbs":10},"caloriesFromMacros":false}"#.utf8)
        let old = try JSONDecoder().decode(SavedProduct.self, from: legacy)
        #expect(old.source == nil && old.unit == .grams)
    }
    @Test func reminderLeadWrapsMidnightWithoutChangingMealTime() {
        let meal = MealReminder(title: "Перекус", hour: 0, minute: 10)
        let time = meal.notificationTime(leadMinutes: 30)
        #expect(time.hour == 23 && time.minute == 40)
        #expect(meal.hour == 0 && meal.minute == 10)
        #expect(meal.notificationTime(leadMinutes: 0).hour == 0)
        #expect(MealReminder(title: "Обед", hour: 14).notificationTime(leadMinutes: 60).hour == 13)
    }
    @Test func invalidReminderPlansCannotSchedule() throws {
        var plan = ReminderPlan()
        #expect(plan.isValid)
        plan.enabled = true
        plan.meals = [MealReminder(title: "Еда", hour: 9, enabled: false)]
        #expect(!plan.isValid)
        plan.enabled = false
        #expect(plan.isValid)
        plan.meals[0].hour = 24
        #expect(!plan.isValid)
        plan = ReminderPlan(); plan.meals.append(plan.meals[0])
        #expect(!plan.isValid)
        plan = ReminderPlan(); plan.leadMinutes = -30
        #expect(!plan.isValid)
    }
    @Test func reminderPlanPersistsExactly() throws {
        var plan = ReminderPlan(); plan.enabled = true; plan.leadMinutes = 15
        #expect(try JSONDecoder().decode(ReminderPlan.self, from: JSONEncoder().encode(plan)) == plan)
    }
    @Test func localRecipeRequestsUseOnlyLocalHostAndPreserveExclusions() throws {
        let request = try OllamaService.makeRecipeRequest(foods: "Яйца, рис", preferences: "Без молока и орехов", servings: 2)
        #expect(request.url?.host == "127.0.0.1")
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect((messages.last?["content"] as? String)?.contains("Без молока и орехов") == true)
        #expect((messages.last?["content"] as? String)?.contains("Порций: 2") == true)
        #expect(throws: (any Error).self) { try OllamaService.makeRecipeRequest(foods: " ", preferences: "", servings: 2) }
        #expect(throws: (any Error).self) { try OllamaService.makeRecipeRequest(foods: "Рис", preferences: "", servings: 0) }
        let photo = try OllamaService.makePantryRequest(jpeg: Data([1, 2]))
        #expect(photo.url?.host == "127.0.0.1")
        #expect(throws: (any Error).self) { try OllamaService.makePantryRequest(jpeg: Data()) }
    }
    private func envelope(_ json: String, done: Bool = true, reason: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["done": done, "done_reason": reason, "message": ["content": json]])
    }
    @Test func validatesPantryAndRecipesBeforeDisplay() throws {
        let pantry = try PantryInventory.decode(envelope(#"{"items":["Яйца","Помидор"],"uncertainties":["Не видна этикетка сыра"]}"#))
        #expect(pantry.items.count == 2)
        let json = #"{"recipes":[{"title":"Рис с яйцом","servings":1,"minutes":15,"ingredients":["Рис готовый, 100 г","Яйцо, 1 шт."],"steps":["Приготовьте яйцо и соедините с рисом."],"missing":[],"note":"Без масла"}]}"#
        #expect(try PantryRecipes.decode(envelope(json)).recipes.count == 1)
        #expect(throws: (any Error).self) { try PantryRecipes.decode(envelope(json, reason: "length")) }
        #expect(throws: (any Error).self) { try PantryRecipes.decode(envelope(json.replacingOccurrences(of: "\"minutes\":15", with: "\"minutes\":-1"))) }
        #expect(throws: (any Error).self) { try PantryRecipes.decode(envelope(#"{"recipes":[]}"#)) }
        #expect(throws: (any Error).self) { try PantryInventory.decode(envelope(#"{"items":[""],"uncertainties":[]}"#)) }
    }
}
