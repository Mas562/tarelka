import Foundation
import Testing
@testable import NutritionCore

struct ReportRecognitionTests {
    @Test func activityChangesDoNotTriggerAutomaticInferenceButFoodAndPreferencesDo() throws {
        let date = Date()
        var personal = PersonalData(); personal.manualTarget = 2500
        let old = CoachContext(date: date, meals: [], personal: personal)
        try personal.mergeActivity([DailyActivity(day: DayKey.string(date), activeCalories: 300, updatedAt: date, source: .manual)])
        let updated = CoachContext(date: date, meals: [], personal: personal)
        #expect(updated != old)
        #expect(!updated.needsAutomaticAdvice(comparedTo: old))
        #expect(updated.remainingMacros?.protein == 140)
        personal.dietaryNotes = "Без орехов"
        #expect(CoachContext(date: date, meals: [], personal: personal).needsAutomaticAdvice(comparedTo: updated))
        let food = Meal(date: date, kind: .snack, name: "Яблоко", weight: 100,
                        ingredients: [Ingredient(name: "Яблоко", grams: 100, per100: Nutrients(calories: 50))])
        #expect(CoachContext(date: date, meals: [food], personal: personal).needsAutomaticAdvice(comparedTo: updated))
    }
    @Test func coachGetsBoundedPriorSuggestionsAndPreviousDaysWithoutMixingTotals() throws {
        let date = Date()
        let food = Meal(date: date.addingTimeInterval(-86400), kind: .dinner, name: "Омлет", weight: 100,
                        ingredients: [Ingredient(name: "Яйца", grams: 100, per100: Nutrients(calories: 150))])
        let context = CoachContext(date: date, meals: [food], personal: PersonalData())
        #expect(context.recentFoods == ["Омлет"])
        #expect(context.eaten.calories == 0)
        let request = try OllamaService.makeCoachRequest(context: context, question: "Можно макароны?", recentAdvice: ["СТАРЫЙ"] + Array(repeating: "Рыба с рисом", count: 4))
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        let user = try #require(messages.last?["content"])
        #expect(user.contains("Рыба с рисом") && user.contains("Можно макароны?"))
        #expect(!user.contains("СТАРЫЙ"))
    }
    @Test func drinkRequestUsesMillilitersAndRequiresValidatedPer100ml() throws {
        let request = try OllamaService.makeDrinkRequest(jpeg: Data([1]), volume: 250, notes: "Без сахара")
        #expect(request.url?.host == "127.0.0.1")
        let bytes = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        #expect((messages.last?["content"] as? String)?.contains("250.0 мл") == true)
        #expect(object["keep_alive"] as? Int == 0)
        func envelope(calories: Double = 50, protein: Double = 3, done: Bool = true) throws -> Data {
            let content = String(decoding: try JSONSerialization.data(withJSONObject: ["name": "Кефир", "per100ml": ["calories": calories, "protein": protein, "fat": 2, "carbs": 4], "assumptions": ["Жирность нужно проверить."]]), as: UTF8.self)
            return try JSONSerialization.data(withJSONObject: ["done": done, "message": ["content": content]])
        }
        let estimate = try DrinkEstimate.decode(envelope())
        #expect(estimate.per100ml.scaled(by: 2.5).calories == 125)
        #expect(throws: (any Error).self) { try DrinkEstimate.decode(envelope(calories: -1)) }
        #expect(throws: (any Error).self) { try DrinkEstimate.decode(envelope(protein: 101)) }
        #expect(throws: (any Error).self) { try DrinkEstimate.decode(envelope(done: false)) }
    }
}
