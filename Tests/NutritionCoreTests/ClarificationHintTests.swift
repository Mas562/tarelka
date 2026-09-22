import Foundation
import Testing
@testable import NutritionCore

struct ClarificationHintTests {
    @Test func questionsFollowDishAndDoNotAssumeOilInFruit() {
        let fruit = MealClarifications.questions(dish: "Банан", ingredients: ["Банан"], assumptions: [])
        #expect(fruit.map(\.id) == ["composition"])
        let meal = MealClarifications.questions(dish: "Курица с рисом", ingredients: [], assumptions: ["Соус неизвестен"])
        #expect(meal.map(\.id) == ["composition", "cooking", "extras"])
        let pastry = MealClarifications.questions(dish: "Вафля", ingredients: [], assumptions: ["Масло и начинка неизвестны"])
        #expect(pastry.map(\.id) == ["composition", "cooking", "filling"])
    }
    @Test func blankAndUnknownAnswersNeverInventFacts() {
        let questions = MealClarifications.questions(dish: "Рис", ingredients: [], assumptions: [])
        #expect(MealClarifications.context(notes: "150 г", questions: questions, answers: ["cooking": "  ", "foreign": "Сахар"]) == "150 г")
        let context = MealClarifications.context(notes: "150 г", questions: questions, answers: ["cooking": "Варёный, без масла"])
        #expect(context.contains("150 г")); #expect(context.contains("Варёный, без масла"))
        #expect(!context.contains("Сахар"))
        let unknown = MealClarifications.answerNotes(questions: questions, answers: ["cooking": "Не знаю"])
        #expect(unknown.contains("Не знаю")); #expect(!unknown.contains("5 г"))
    }
    @Test func refinementAnswersSurviveRequestBeyondOldLimit() throws {
        let questions = MealClarifications.questions(dish: "Рис", ingredients: [], assumptions: [])
        let context = MealClarifications.context(notes: String(repeating: "я", count: 2000), questions: questions, answers: ["cooking": "Без масла"])
        let request = try OllamaService.makeRequest(jpeg: Data([1]), weight: 150, notes: context)
        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self).contains("Без масла"))
    }
    private func budget(eaten: Double) -> DayBudget { DayBudget(base: 2000, active: 0, creditsActivity: true, deficit: 0, eaten: eaten) }
    @Test func proteinHintRecognizesNearlyUsedFatBudget() throws {
        let eaten = Nutrients(calories: 900, protein: 25, fat: 62, carbs: 60)
        let hint = try #require(MacroHint.make(eaten: eaten, budget: budget(eaten: 900), hasPreferences: false))
        #expect(hint.title == "Белок с меньшим количеством жира")
        #expect(hint.message.contains("75")); #expect(hint.message.contains("творог"))
        let restricted = try #require(MacroHint.make(eaten: eaten, budget: budget(eaten: 900), hasPreferences: true))
        #expect(!restricted.message.contains("творог")); #expect(!restricted.message.contains("рыбу"))
        #expect(restricted.message.contains("ограничений"))
    }
    @Test func hintsHandleEmptyReachedAndDifferentMacroBalances() throws {
        let empty = try #require(MacroHint.make(eaten: Nutrients(), budget: budget(eaten: 0), hasPreferences: false))
        #expect(empty.title == "Начнём с записей")
        let reached = try #require(MacroHint.make(eaten: Nutrients(calories: 2100, protein: 20), budget: budget(eaten: 2100), hasPreferences: false))
        #expect(reached.title == "Продолжай в обычном ритме")
        for (p, f, c, title) in [(10.0, 40.0, 150.0, "Можно добавить источник белка"), (80, 50, 30, "Есть место для гарнира"), (80, 10, 200, "Жиры тоже часть питания"), (85, 60, 230, "БЖУ близки к ориентирам")] {
            #expect(MacroHint.make(eaten: Nutrients(calories: 1500, protein: p, fat: f, carbs: c), budget: budget(eaten: 1500), hasPreferences: false)?.title == title)
        }
    }
}
