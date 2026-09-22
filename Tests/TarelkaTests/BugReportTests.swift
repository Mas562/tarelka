import Foundation
import SwiftUI
import Testing
import NutritionCore
@testable import Tarelka

@MainActor
struct BugReportTests {
    private func withModel(_ test: (AppModel) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(AppModel(directory: directory))
    }
    private func drink(date: Date = Date()) -> Meal {
        Meal(date: date, kind: .snack, name: "Кефир", weight: 250,
             ingredients: [Ingredient(name: "Кефир", amount: 250, unit: .milliliters,
                                      per100: Nutrients(calories: 50, protein: 3, fat: 2, carbs: 4))])
    }
    @Test func lateTextFieldCallbacksAfterDeletionDoNotCrashOrChangeAnotherRow() throws {
        try withModel { model in
            let first = IngredientDraft(Ingredient(name: "Первый", grams: 70, per100: Nutrients(calories: 100)))
            let second = IngredientDraft(Ingredient(name: "Второй", grams: 40, per100: Nutrients(calories: 200)))
            model.drafts = [first, second]
            let oldFirst = model.binding(for: first)
            let oldSecond = model.binding(for: second)
            model.drafts.removeFirst()
            #expect(oldFirst.name.wrappedValue == "Первый")
            oldFirst.name.wrappedValue = "Запоздалый ввод"
            #expect(model.drafts.count == 1 && model.drafts[0].name == "Второй")
            oldSecond.grams.wrappedValue = "90"
            #expect(model.drafts[0].grams == "90")
            model.resetDraft()
            oldSecond.grams.wrappedValue = "500"
            #expect(oldSecond.name.wrappedValue == "Второй")
            #expect(model.drafts.isEmpty)
        }
    }
    @Test func replacementAndReorderKeepBindingsAttachedToTheirOwnIngredient() throws {
        try withModel { model in
            let first = IngredientDraft(), second = IngredientDraft()
            model.drafts = [first, second]
            let binding = model.binding(for: first)
            model.drafts.reverse()
            binding.name.wrappedValue = "Сыр"
            #expect(model.drafts.last?.name == "Сыр")
            model.addProduct(SavedProduct(name: "Творог", per100: Nutrients(calories: 90)), grams: 100, replacing: first.id)
            binding.name.wrappedValue = "Поздний ввод"
            #expect(model.drafts.last?.name == "Творог")
        }
    }
    @Test func nextMealGetsCurrentTimeButEditingAndChosenDatesArePreserved() throws {
        try withModel { model in
            let first = Date(timeIntervalSince1970: 1000), next = first.addingTimeInterval(3600)
            model.beginNewMeal(at: first)
            #expect(model.mealDate == first)
            model.resetDraft(); model.beginNewMeal(at: next)
            #expect(model.mealDate == next)
            model.weight = "100"
            model.refreshNewMealDate(at: next.addingTimeInterval(600))
            #expect(model.mealDate == next.addingTimeInterval(600))
            model.hasResult = true; model.mealDate = first
            model.refreshNewMealDate(at: next)
            #expect(model.mealDate == first)
            model.resetDraft(); model.editingID = UUID(); model.mealDate = first
            model.beginNewMeal(at: next); model.refreshNewMealDate(at: next)
            #expect(model.mealDate == first)
        }
    }
    @Test func drinkPhotoSurvivesEditReplacementRemovalAndReload() throws {
        try withModel { model in
            var meal = drink()
            let first = Data([1, 2, 3]), replacement = Data([4, 5, 6])
            try model.saveDrink(meal, photoChange: .replace(first))
            meal = try #require(model.repository.load().first)
            let firstURL = try #require(model.repository.photoURL(meal.photoFilename))
            #expect(try Data(contentsOf: firstURL) == first)
            meal.name = "Кефир вечером"
            try model.saveDrink(meal)
            #expect(try Data(contentsOf: firstURL) == first)
            try model.saveDrink(meal, photoChange: .replace(replacement))
            meal = try #require(model.repository.load().first)
            let secondURL = try #require(model.repository.photoURL(meal.photoFilename))
            #expect(!FileManager.default.fileExists(atPath: firstURL.path))
            #expect(try Data(contentsOf: secondURL) == replacement)
            #expect(meal.total.calories == 125 && meal.isDrink)
            try model.saveDrink(meal, photoChange: .remove)
            #expect(try model.repository.load().first?.photoFilename == nil)
            #expect(!FileManager.default.fileExists(atPath: secondURL.path))
        }
    }
    @Test func failedDrinkSaveKeepsOldPhotoAndRollsBackNewPhoto() throws {
        try withModel { model in
            try model.saveDrink(drink(), photoChange: .replace(Data([1])))
            let meal = try #require(model.meals.first)
            let oldPhoto = try #require(model.repository.photoURL(meal.photoFilename))
            // A directory at the journal path forces the atomic journal write to fail.
            try FileManager.default.removeItem(at: model.repository.journalURL)
            try FileManager.default.createDirectory(at: model.repository.journalURL, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) { try model.saveDrink(meal, photoChange: .replace(Data([2]))) }
            #expect(try Data(contentsOf: oldPhoto) == Data([1]))
            #expect(try FileManager.default.contentsOfDirectory(atPath: model.repository.photosURL.path).count == 1)
            #expect(model.meals.first?.photoFilename == meal.photoFilename)
        }
    }
    @Test func activityReplacesSavedValueAndUpdatesBudgetOnce() throws {
        try withModel { model in
            let date = Date()
            #expect(model.personal.saveProfile(nil, target: 2500))
            #expect(model.personal.saveManualActivity(calories: 300, date: date))
            #expect(model.personal.data.budget(on: date, eaten: 500)?.remaining == 2300)
            #expect(model.personal.saveManualActivity(calories: 400, date: date))
            #expect(model.personal.data.budget(on: date, eaten: 500)?.remaining == 2400)
            #expect(model.personal.data.activity.count == 1)
        }
    }
}
