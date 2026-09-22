import Foundation
import Testing
@testable import NutritionCore

struct DrinkTests {
    private let label = Nutrients(calories: 46, protein: 0.5, fat: 0.1, carbs: 11)
    private func drink(_ volume: Double, date: Date = Date()) -> Meal {
        Meal(date: date, kind: .snack, name: "Тестовый сок", weight: volume,
             ingredients: [Ingredient(name: "Тестовый сок", amount: volume, unit: .milliliters, per100: label)])
    }

    @Test func volumeScalesAllNutrientsAndAllowsWater() throws {
        let juice = drink(250)
        try juice.validate()
        #expect(juice.isDrink && juice.unit.symbol == "мл")
        #expect(juice.total == Nutrients(calories: 115, protein: 1.25, fat: 0.25, carbs: 27.5))
        let water = SavedProduct(name: "Вода", per100: Nutrients(), unit: .milliliters)
        let meal = Meal(date: Date(), kind: .snack, name: water.name, weight: 330,
                        ingredients: [water.portion(amount: 330)])
        try meal.validate()
        #expect(meal.total == Nutrients())
        for volume in [0.0, -1, .infinity, 20_001] {
            #expect(throws: (any Error).self) { try drink(volume).validate() }
        }
    }

    @Test func gramsAndMillilitersCannotBeAddedAsOneWeight() {
        let liquid = drink(250).ingredients[0]
        let food = Ingredient(name: "Сыр", grams: 40, per100: label)
        #expect(throws: (any Error).self) { try NutritionMath.validate([food, liquid], weight: 290) }
        #expect(throws: (any Error).self) { try NutritionMath.normalize([food, liquid], to: 300) }
    }

    @Test func drinksPersistWithFoodAndCanBeEditedAndDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MealRepository(directory: directory)
        let food = Meal(date: Date(timeIntervalSince1970: 1000), kind: .lunch, name: "Блюдо", weight: 100,
                        ingredients: [Ingredient(name: "Продукт", grams: 100, per100: label)])
        var juice = drink(250, date: Date(timeIntervalSince1970: 2000))
        try repository.save([juice, food])
        #expect(try repository.load() == [juice, food])
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.journalURL)) as? [String: Any])
        #expect(json["version"] as? Int == 2)
        juice.weight = 500; juice.ingredients[0].amount = 500
        try repository.save([juice, food])
        #expect(try repository.load().first?.total.calories == 230)
        try repository.save([food])
        #expect(try repository.load() == [food])
    }

    @Test func previousFoodAndProductJSONStillDecodeAsGrams() throws {
        let ingredientJSON = #"{"id":"A13D4B53-FAC4-4E53-8E99-552FBFAEC801","name":"Сыр","grams":40,"per100":{"calories":350,"protein":25,"fat":27,"carbs":0}}"#
        let ingredient = try JSONDecoder().decode(Ingredient.self, from: Data(ingredientJSON.utf8))
        #expect(ingredient.unit == .grams && ingredient.amount == 40)
        #expect(ingredient.total.calories == 140)
        let productJSON = #"{"id":"A13D4B53-FAC4-4E53-8E99-552FBFAEC801","name":"Сыр","per100":{"calories":350,"protein":25,"fat":27,"carbs":0},"caloriesFromMacros":false}"#
        let product = try JSONDecoder().decode(SavedProduct.self, from: Data(productJSON.utf8))
        #expect(product.unit == .grams)
        #expect(product.portion(grams: 40).total == ingredient.total)
    }

    @Test func savedDrinkKeepsLabelBasisAfterRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = PersonalRepository(directory: directory)
        var data = PersonalData()
        data.products = [SavedProduct(name: "Сок", per100: label, unit: .milliliters)]
        try repository.save(data)
        let restored = try repository.load()
        #expect(restored.version == 2)
        #expect(restored.products == data.products)
        #expect(restored.products[0].portion(amount: 250).total.calories == 115)
    }

    @Test func drinkChangesDailyBudgetAndCoachIncludesVolume() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        var personal = PersonalData()
        personal.manualTarget = 2500
        var settings = BudgetSettings(); settings.accounting = .watch; personal.budgetSettings = settings
        try personal.mergeActivity([DailyActivity(day: DayKey.string(date), activeCalories: 300, updatedAt: date, source: .manual)])
        let food = Meal(date: date, kind: .lunch, name: "Блюдо", weight: 100,
                        ingredients: [Ingredient(name: "Продукт", grams: 100, per100: Nutrients(calories: 500))])
        let context = CoachContext(date: date, meals: [food, drink(250, date: date)], personal: personal)
        #expect(context.eaten.calories == 615)
        #expect(context.remainingCalories == 2185)
        #expect(context.meals.flatMap(\.ingredients).contains("Тестовый сок — 250 мл"))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let otherDay = CoachContext(date: tomorrow, meals: [food, drink(250, date: date)], personal: personal)
        #expect(otherDay.eaten.calories == 0)
    }
}
