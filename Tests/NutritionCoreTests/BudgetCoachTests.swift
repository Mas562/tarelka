import Foundation
import Testing
@testable import NutritionCore

struct BudgetCoachTests {
    private let date = Date(timeIntervalSince1970: 1_788_865_200)
    private var profile: CalorieProfile { CalorieProfile(height: 180, weight: 80, age: 30, sex: .male, activity: .high) }
    private func personal(active: Double? = 300, goal: NutritionGoal = .maintain) throws -> PersonalData {
        var data = PersonalData(); data.profile = profile
        data.budgetSettings = BudgetSettings(accounting: .watch, goal: goal)
        if let active { try data.mergeActivity([DailyActivity(day: DayKey.string(date), activeCalories: active, updatedAt: date, source: .manual)]) }
        return data
    }
    @Test func burnedCaloriesIncreaseRemainingAndDoNotChangeEaten() throws {
        var data = try personal(); data.manualTarget = 2500
        let budget = try #require(data.budget(on: date, eaten: 500))
        #expect(budget.remaining == 2300)
        #expect(budget.target == 2800)
        #expect(budget.eaten == 500)
        #expect(budget.netEaten == 200)
        #expect(DailyBudget.remaining(target: 2500, eaten: 500, activeCalories: 300) == 2300)
    }
    @Test func watchModeAvoidsActivityMultiplierAndReplacesImports() throws {
        var data = try personal(active: 600)
        #expect(data.budget(on: date, eaten: 500)?.remaining == 1880) // 1780 + 600 − 500
        data.profile?.activity = .low
        #expect(data.budget(on: date, eaten: 500)?.remaining == 1880)
        try data.mergeActivity([DailyActivity(day: DayKey.string(date), activeCalories: 750, updatedAt: date.addingTimeInterval(60), source: .transferFile)])
        #expect(data.budget(on: date, eaten: 500)?.remaining == 2030)
        data.budgetSettings?.accounting = .estimated
        #expect(data.budget(on: date, eaten: 500)?.remaining == 1636) // 2136 − 500
        #expect(data.budget(on: date, eaten: 500)?.creditedActivity == 0)
    }
    @Test func missingAndZeroActivityDifferAndOtherDaysNeverLeak() throws {
        var data = try personal(active: nil)
        #expect(data.budget(on: date, eaten: 0)?.awaitingActivity == true)
        data = try personal(active: 0)
        #expect(data.budget(on: date, eaten: 0)?.awaitingActivity == false)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: date))
        #expect(data.budget(on: tomorrow, eaten: 0)?.active == nil)
        #expect(data.budget(on: tomorrow, eaten: 0)?.awaitingActivity == true)
    }
    @Test func gentleGoalHasLimitedDeficitAndRespectsManualGoal() throws {
        var data = try personal(active: 600, goal: .gentleLoss)
        #expect(data.budget(on: date, eaten: 500)?.deficit == 238)
        #expect(data.budget(on: date, eaten: 500)?.remaining == 1642)
        data.activity[0].activeCalories = 2000
        #expect(data.budget(on: date, eaten: 500)?.deficit == 300)
        data.manualTarget = 2500
        #expect(data.budget(on: date, eaten: 500)?.deficit == 0)
        data.manualTarget = nil; data.activity = []
        data.profile = CalorieProfile(height: 165, weight: 60, age: 60, sex: .female, activity: .low)
        #expect(data.budget(on: date, eaten: 0)?.deficit == 0) // Resting estimate already below 1200.
        data.profile = CalorieProfile(height: 190, weight: 60, age: 25, sex: .male, activity: .low)
        #expect(data.budget(on: date, eaten: 0)?.deficit == 0) // Low BMI: no automatic reduction.
        #expect(data.budget(on: date, eaten: .nan) == nil)
    }
    @Test func oldPersonalFilesMigrateWithoutDroppingData() throws {
        var original = try personal(); original.budgetSettings = nil
        original.products = [SavedProduct(name: "Сыр", per100: Nutrients(calories: 350, protein: 25, fat: 27))]
        let encoded = try JSONEncoder().encode(original)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("budgetSettings"))
        var decoded = try JSONDecoder().decode(PersonalData.self, from: encoded)
        #expect(decoded.settings.accounting == .watch)
        #expect(decoded.products == original.products)
        #expect(decoded.activity == original.activity)
        decoded.budgetSettings = BudgetSettings(accounting: .watch, goal: .gentleLoss)
        decoded.dietaryNotes = "Без орехов"; decoded.coachEnabled = false
        #expect(try JSONDecoder().decode(PersonalData.self, from: JSONEncoder().encode(decoded)) == decoded)
    }
    @Test func coachUsesOnlySelectedDayAndBoundsDetailsWithoutLosingTotals() throws {
        let ingredient = Ingredient(name: String(repeating: "Я", count: 100), grams: 100, per100: Nutrients(calories: 200, protein: 10, fat: 8, carbs: 22))
        var meals = (0..<12).map { index in Meal(date: date, kind: .snack, name: "Блюдо \(index)", weight: 100, ingredients: [ingredient]) }
        meals.append(Meal(date: date.addingTimeInterval(-86400), kind: .snack, name: "Вчерашнее", weight: 100, ingredients: [ingredient]))
        let context = CoachContext(date: date, meals: meals, personal: try personal())
        #expect(context.eaten.calories == 2400)
        #expect(context.totalMealCount == 12)
        #expect(context.meals.count == 8)
        #expect(!context.meals.contains { $0.name == "Вчерашнее" })
        #expect(context.meals.allSatisfy { $0.ingredients[0].count < 80 })
        #expect(context.targetCalories == 2080)
        #expect(context.remainingCalories == -320)
    }
    @Test func coachRequestIsLocalStructuredAndDoesNotSendProfileOrPhotos() throws {
        let context = CoachContext(date: date, meals: [], personal: try personal())
        let request = try OllamaService.makeCoachRequest(context: context, question: "Что съесть?")
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let bytes = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(body["model"] as? String == "qwen3:4b-instruct-2507-q4_K_M")
        #expect(body["think"] == nil)
        #expect(body["keep_alive"] as? Int == 0)
        #expect(body["format"] is [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.allSatisfy { $0["images"] == nil })
        let user = try #require(messages.last?["content"] as? String)
        #expect(user.contains("Что съесть?"))
        #expect(!user.contains("height")); #expect(!user.contains("weight")); #expect(!user.contains("age"))
    }
    @Test func adviceRequiresCompleteBoundedFields() throws {
        let fields = ["headline": "Твой следующий шаг", "observation": "В дневнике есть выпечка.", "next_meal": "Рыба с овощами и рисом.", "swap": "Йогурт с фруктом.", "encouragement": "Подбирай удобный тебе ритм."]
        func envelope(_ object: [String: String], done: Bool = true, reason: String = "stop") throws -> Data {
            let content = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            return try JSONSerialization.data(withJSONObject: ["done": done, "done_reason": reason, "message": ["content": content]])
        }
        #expect(try NutritionAdvice.decode(envelope(fields)).next_meal == fields["next_meal"])
        #expect(throws: (any Error).self) { try NutritionAdvice.decode(envelope(fields, done: false)) }
        #expect(throws: (any Error).self) { try NutritionAdvice.decode(envelope(fields, reason: "length")) }
        var invalid = fields; invalid["swap"] = nil
        #expect(throws: (any Error).self) { try NutritionAdvice.decode(envelope(invalid)) }
        invalid = fields; invalid["headline"] = String(repeating: "я", count: 91)
        #expect(throws: (any Error).self) { try NutritionAdvice.decode(envelope(invalid)) }
        invalid = fields; invalid["observation"] = "  "
        #expect(throws: (any Error).self) { try NutritionAdvice.decode(envelope(invalid)) }
    }
}
