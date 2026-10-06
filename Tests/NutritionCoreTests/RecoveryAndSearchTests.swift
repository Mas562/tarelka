import Foundation
import Testing
@testable import NutritionCore

struct RecoveryAndSearchTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func meal(_ name: String, calories: Double = 200) -> Meal {
        Meal(date: Date(), kind: .lunch, name: name, weight: 100,
             ingredients: [Ingredient(name: name, grams: 100, per100: Nutrients(calories: calories, protein: 10, fat: 5, carbs: 20))])
    }

    @Test func damagedRowIsMovedAsideAndTheRestOfTheDiaryStaysEditable() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = MealRepository(directory: folder)
        let good = meal("Суп")
        try repository.save([good])
        // An older or hand-edited row whose ingredient weight no longer matches the portion.
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.journalURL)) as? [String: Any])
        var rows = try #require(object["meals"] as? [[String: Any]])
        var broken = rows[0]; broken["id"] = UUID().uuidString; broken["weight"] = 999; broken["name"] = "Повреждённая"
        rows.append(broken); rows.append(["not": "a meal"]); object["meals"] = rows
        try JSONSerialization.data(withJSONObject: object).write(to: repository.journalURL)

        #expect(try repository.load() == [good])
        #expect(try repository.recoverUnreadable() == 2)
        let kept = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.unreadableURL)) as? [[String: Any]])
        #expect(kept.count == 2 && kept.contains { $0["name"] as? String == "Повреждённая" })
        #expect(try repository.recoverUnreadable() == 0)
        let added = meal("Чай")
        #expect(try repository.save([good, added], replacing: [good]).count == 2)
        #expect(try repository.load().count == 2)
    }

    @Test func newerOrUnparseableJournalIsStillProtected() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = MealRepository(directory: folder)
        try PrivateStorage.prepareDirectory(folder)
        let newer = Data(#"{"version":3,"meals":[]}"#.utf8)
        try newer.write(to: repository.journalURL)
        #expect(throws: (any Error).self) { try repository.recoverUnreadable() }
        #expect(try Data(contentsOf: repository.journalURL) == newer)
    }

    @Test func partlyDamagedPersonalFileKeepsValidDataAndABackup() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = PersonalRepository(directory: folder)
        var data = PersonalData()
        let cheese = SavedProduct(name: "Сыр", per100: Nutrients(calories: 350, protein: 25, fat: 27))
        data.products = [cheese]
        data.profile = CalorieProfile(height: 180, weight: 80, age: 30, sex: .male, activity: .low)
        try repository.save(data)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: repository.url)) as? [String: Any])
        var products = try #require(object["products"] as? [Any])
        products.append(["name": "Без идентификатора"])
        object["products"] = products
        try JSONSerialization.data(withJSONObject: object).write(to: repository.url)

        #expect(try repository.load().products == [cheese])
        let backup = try #require(try repository.recoverDamaged())
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(try repository.recoverDamaged() == nil)
        #expect(try repository.load().profile == data.profile)
    }

    @Test func twoCopiesKeepEachOthersPersonalChanges() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let repository = PersonalRepository(directory: folder)
        let base = try repository.save(PersonalData())
        var first = base; first.products = [SavedProduct(name: "Сыр", per100: Nutrients(calories: 350, protein: 25, fat: 27))]
        var second = base; second.manualTarget = 2000
        try repository.save(first, replacing: base)
        let merged = try repository.save(second, replacing: base)
        #expect(merged.products == first.products && merged.manualTarget == 2000)
        #expect(try repository.load() == merged)
        var stale = base; stale.manualTarget = 2500
        #expect(throws: PersonalError.storageConflict) { try repository.save(stale, replacing: base) }
        #expect(try repository.load().manualTarget == 2000)
    }

    @Test func watchModeWithoutActivityNeverStopsAtRestingExpenditure() throws {
        var data = PersonalData()
        data.profile = CalorieProfile(height: 180, weight: 80, age: 30, sex: .male, activity: .high)
        let budget = try #require(data.budget(on: Date(), eaten: 0))
        #expect(budget.awaitingActivity && budget.base == 1780 && budget.target == 2136)
        // Someone who logs activity never gets calories they have not burned yet, e.g. right after midnight.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        data.activity = [DailyActivity(day: DayKey.string(yesterday), activeCalories: 526, updatedAt: Date(), source: .manual)]
        let newDay = try #require(data.budget(on: Date(), eaten: 0))
        #expect(newDay.awaitingActivity && newDay.provisionalActivity == 0 && newDay.target == 1780)
        data.activity = []
        data.manualTarget = 2000
        #expect(data.budget(on: Date(), eaten: 0)?.target == 2000) // A manual base is the user's own choice.
    }

    @Test func russianSearchMatchesWholeFoodsFirst() throws {
        let catalog = FoodCatalog.shared
        #expect(catalog.search("горох").first?.name.hasPrefix("Pea") == true)
        #expect(!catalog.search("горох", limit: 8000).contains { $0.name.hasPrefix("Pears") || $0.name.hasPrefix("Peanuts") })
        #expect(catalog.search("яйцо").first?.name.hasPrefix("Egg") == true)
        #expect(!catalog.search("яйцо", limit: 8000).contains { $0.name.hasPrefix("Eggplant") })
        #expect(catalog.search("вода").first?.name.hasPrefix("Water") == true)
        #expect(!catalog.search("вода", limit: 8000).contains { $0.name.hasPrefix("Watermelon") })
        #expect(FoodCatalog.localized("Egg, white, raw, fresh") == "Яйцо · белок · сырое · свежее")
        #expect(catalog.search("белок").contains { $0.name == "Egg, white, raw, fresh" })
    }
}
