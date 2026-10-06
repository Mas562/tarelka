import Foundation
import Testing
@testable import NutritionCore

struct JournalConcurrencyTests {
    @Test func anotherWriterIsRejectedWithoutBlockingOrTouchingTheJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MealRepository(directory: directory)
        let meal = Meal(date: Date(), kind: .lunch, name: "Тест", weight: 100,
                        ingredients: [Ingredient(name: "Тест", grams: 100, per100: Nutrients(calories: 100))])
        try repository.save([meal])
        try PrivateStorage.withExclusiveLock(at: directory.appendingPathComponent(".meals.lock")) {
            #expect(throws: FoodError.self) { try repository.save([], replacing: [meal]) }
            let stored = try repository.load()
            #expect(stored == [meal])
        }
        // Releasing the lock permits the next operation, including after a throw.
        #expect(try repository.save([], replacing: [meal]).isEmpty)
    }

    @Test func mixedServingHeadersNeverContaminatePer100Values() {
        for header in ["На порцию 30 г", "В одной порции", "Per serving (30g)", "Serving size 30 g", "На 30 г", "Per 250 ml", "На упаковку"] {
            for headerFirst in [true, false] {
                let serving = "\(header)\nБелки 6 г\nЖиры 3 г\nУглеводы 15 г"
                let energy = "Энергетическая ценность на 100 г: 400 ккал"
                let scan = NutritionLabelParser.parse(text: headerFirst ? serving + "\n" + energy : energy + "\n" + serving)
                #expect(scan.foundCount == 0 && scan.unit == nil, "Ambiguous header: \(header)")
            }
        }
        let valid = NutritionLabelParser.parse(text: "Масса нетто 30 г\nНа 100 г\nБелки 20 г\nЖиры 10 г\nУглеводы 50 г\n400 ккал")
        #expect(valid.foundCount == 4 && valid.protein == 20 && valid.calories == 400)
    }
}
