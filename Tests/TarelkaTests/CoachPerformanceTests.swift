import Foundation
import Testing
import NutritionCore
@testable import Tarelka

private actor ControlledAdvisor {
    var calls = 0
    private var pending: [CheckedContinuation<NutritionAdvice, any Error>] = []
    func answer() async throws -> NutritionAdvice {
        calls += 1
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func succeed(_ answer: NutritionAdvice) { pending.removeFirst().resume(returning: answer) }
    func fail() { pending.removeFirst().resume(throwing: LocalModelError.unavailable) }
}

@MainActor
struct CoachPerformanceTests {
    private func snapshot(calories: Double = 100) -> CoachContext {
        let meal = Meal(date: Date(), kind: .lunch, name: "Обед", weight: 100, ingredients: [Ingredient(name: "Рис", grams: 100, per100: Nutrients(calories: calories))])
        return CoachContext(date: Date(), meals: [meal], personal: PersonalData())
    }
    private func answer() throws -> NutritionAdvice {
        try JSONDecoder().decode(NutritionAdvice.self, from: Data(#"{"headline":"Совет","observation":"Записи дня","next_meal":"Рыба с рисом или фасоль с овощами","swap":"Йогурт с фруктом","encouragement":"Выбери удобный вариант"}"#.utf8))
    }
    private func settle(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Coach state did not settle")
    }
    @Test func automaticChangesAndRepeatedClicksDoNotLaunchExtraWork() async throws {
        let backend = ControlledAdvisor()
        let coach = CoachStore(advisor: { _, _, _ in try await backend.answer() })
        coach.schedule(snapshot()); coach.schedule(nil); coach.schedule(snapshot(calories: 500))
        await Task.yield()
        #expect(await backend.calls == 0)
        coach.schedule(snapshot(), question: "Что съесть?", force: true)
        try await settle { await backend.calls == 1 }
        coach.schedule(snapshot(calories: 500), force: true)
        coach.schedule(snapshot()); coach.schedule(nil)
        #expect(coach.loading)
        #expect(await backend.calls == 1)
        await backend.succeed(try answer())
        try await settle { !coach.loading }
        let saved = coach.advice
        coach.schedule(snapshot(calories: 800))
        #expect(coach.advice == saved && coach.context?.eaten.calories == 100)
        #expect(await backend.calls == 1)
    }
    @Test func cancelledLateReplyCannotReplaceTheNewAnswer() async throws {
        let backend = ControlledAdvisor()
        let coach = CoachStore(advisor: { _, _, _ in try await backend.answer() })
        coach.schedule(snapshot(), question: "Старый", force: true)
        try await settle { await backend.calls == 1 }
        coach.cancel()
        #expect(!coach.loading)
        coach.schedule(snapshot(calories: 700), question: "Новый", force: true)
        try await settle { await backend.calls == 2 }
        await backend.succeed(try answer()) // Cancelled server response arrives late.
        await Task.yield()
        #expect(coach.advice == nil && coach.loading)
        await backend.succeed(try answer())
        try await settle { !coach.loading }
        #expect(coach.context?.eaten.calories == 700 && coach.answeredQuestion == "Новый")
    }
    @Test func failedRefreshKeepsLastSuccessfulAdvice() async throws {
        let backend = ControlledAdvisor()
        let coach = CoachStore(advisor: { _, _, _ in try await backend.answer() })
        coach.schedule(snapshot(), force: true)
        try await settle { await backend.calls == 1 }
        await backend.succeed(try answer())
        try await settle { !coach.loading }
        let saved = coach.advice
        coach.schedule(snapshot(calories: 600), force: true)
        try await settle { await backend.calls == 2 }
        await backend.fail()
        try await settle { !coach.loading }
        #expect(coach.advice == saved && coach.context?.eaten.calories == 100)
        #expect(coach.error != nil)
    }
}
