import Foundation
import Testing
import NutritionCore
@testable import Tarelka

@MainActor
struct AuditRegressionTests {
    private func withDirectory(_ test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(directory)
    }
    private func food() -> Meal {
        Meal(date: Date(), kind: .lunch, name: "Картофель", weight: 100,
             ingredients: [Ingredient(name: "Картофель", grams: 100,
                                      per100: Nutrients(calories: 80, protein: 2, carbs: 18))])
    }

    @Test func independentCopiesKeepBothAdditionsAndDoNotResurrectDeletedMeals() throws {
        try withDirectory { directory in
            let first = AppModel(directory: directory), second = AppModel(directory: directory)
            first.repeatMeal(food()); second.repeatMeal(food())
            #expect(first.errorMessage == nil && second.errorMessage == nil)
            #expect(try first.repository.load().count == 2)
            let deleted = try #require(first.meals.first)
            first.deleteMeal(deleted)
            #expect(try first.repository.load().count == 1)
            second.repeatMeal(food())
            let stored = try first.repository.load()
            #expect(stored.count == 2 && !stored.contains { $0.id == deleted.id })
            #expect(second.meals == stored)
        }
    }

    @Test func staleFoodEditorCannotOverwriteAnEditEvenAfterMenuRefresh() throws {
        try withDirectory { directory in
            let seed = food()
            try MealRepository(directory: directory).save([seed])
            let first = AppModel(directory: directory), second = AppModel(directory: directory)
            first.edit(seed); second.edit(seed)
            first.dishName = "Правка первой копии"; first.saveMeal()
            #expect(first.errorMessage == nil)
            second.repeatMeal(food()) // Refreshes meals, but not the original editor snapshot.
            second.dishName = "Устаревшая правка"; second.saveMeal()
            #expect(second.errorMessage != nil && second.hasResult)
            #expect(try first.repository.load().first { $0.id == seed.id }?.name == "Правка первой копии")
            second.deleteMeal(seed)
            #expect(try first.repository.load().contains { $0.id == seed.id })
        }
    }

    @Test func staleDrinkEditorCannotOverwriteAnEditAfterMenuRefresh() throws {
        try withDirectory { directory in
            var seed = food()
            seed.ingredients = [Ingredient(name: "Кефир", amount: 100, unit: .milliliters, per100: Nutrients(calories: 50))]
            try MealRepository(directory: directory).save([seed])
            let first = AppModel(directory: directory), second = AppModel(directory: directory)
            var changed = seed; changed.name = "Новая версия"
            try first.saveDrink(changed, original: seed)
            second.repeatMeal(seed)
            var stale = seed; stale.name = "Старая версия"
            #expect(throws: FoodError.self) { try second.saveDrink(stale, original: seed) }
            #expect(try first.repository.load().first { $0.id == seed.id }?.name == "Новая версия")
        }
    }

    @Test func unavailableFoodPhotoIsPreservedUntilExplicitRemoval() throws {
        try withDirectory { directory in
            let repository = MealRepository(directory: directory)
            var seed = food(); seed.photoFilename = try repository.savePhoto(Data([1, 2, 3]))
            try repository.save([seed])
            let url = try #require(repository.photoURL(seed.photoFilename))
            let temporary = directory.appendingPathComponent("temporarily-unavailable.jpg")
            try FileManager.default.moveItem(at: url, to: temporary)
            let model = AppModel(directory: directory)
            model.edit(seed)
            #expect(model.photoData == nil && model.notice != nil)
            try FileManager.default.moveItem(at: temporary, to: url)
            model.dishName = "Блюдо после правки"; model.saveMeal()
            let stored = try #require(repository.load().first)
            #expect(model.errorMessage == nil && stored.photoFilename == seed.photoFilename)
            #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
            model.edit(stored); model.removePhoto(); model.saveMeal()
            #expect(try repository.load().first?.photoFilename == nil)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func rejectedFoodEditKeepsOriginalPhotoAndCleansUpReplacement() throws {
        try withDirectory { directory in
            let repository = MealRepository(directory: directory)
            var seed = food(); seed.photoFilename = try repository.savePhoto(Data([1]))
            try repository.save([seed])
            let model = AppModel(directory: directory); model.edit(seed)
            var changed = seed; changed.name = "Изменено другой копией"
            try repository.save([changed], replacing: [seed])
            model.photoData = Data([2]); model.saveMeal()
            #expect(model.errorMessage != nil && model.hasResult)
            let url = try #require(repository.photoURL(seed.photoFilename))
            #expect(try Data(contentsOf: url) == Data([1]))
            #expect(try FileManager.default.contentsOfDirectory(atPath: repository.photosURL.path).count == 1)
        }
    }

    @Test func historicalDiaryDateSurvivesAppearanceManualEntryAndSave() throws {
        try withDirectory { directory in
            let model = AppModel(directory: directory)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            model.selectedDay = yesterday; model.openNewMeal(on: model.selectedDay)
            model.beginNewMeal(); model.weight = "100"; model.refreshNewMealDate(); model.startManual()
            #expect(model.mealDate == yesterday)
            model.drafts = food().ingredients.map(IngredientDraft.init); model.dishName = "Картофель"
            model.saveMeal()
            let stored = try model.repository.load()
            #expect(stored.first?.date == yesterday)
            #expect(model.selectedDay == yesterday)
            let next = yesterday.addingTimeInterval(172800)
            model.beginNewMeal(at: next)
            #expect(model.mealDate == next)
            model.weight = "150"; model.openNewMeal(on: yesterday)
            #expect(model.mealDate == next && model.weight == "150")
        }
    }

    @Test func manualActivityOverridesImportedFutureTimestampAndPersists() throws {
        try withDirectory { directory in
            let now = Date(), repository = PersonalRepository(directory: directory)
            var data = PersonalData(); data.manualTarget = 2500
            data.activity = [DailyActivity(day: DayKey.string(now), activeCalories: 100,
                                           updatedAt: now.addingTimeInterval(86400), source: .appleHealth)]
            try repository.save(data)
            let model = AppModel(directory: directory)
            #expect(model.personal.saveManualActivity(calories: 300, date: now))
            #expect(model.personal.data.budget(on: now, eaten: 500)?.remaining == 2300)
            let stored = try repository.load()
            #expect(stored.activity.count == 1 && stored.activity[0].activeCalories == 300)
            #expect(stored.activity[0].source == .manual)
        }
    }
}
