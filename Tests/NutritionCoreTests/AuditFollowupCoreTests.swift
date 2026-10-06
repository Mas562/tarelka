import Foundation
import Testing
@testable import NutritionCore

struct AuditFollowupCoreTests {
    private func export(_ body: String) -> Data {
        Data("<?xml version=\"1.0\"?><HealthData><ExportDate value=\"2026-09-08 18:00:00 +0500\"/>\(body)</HealthData>".utf8)
    }
    private func summary(_ day: String, _ calories: String, unit: String = "kcal") -> String {
        "<ActivitySummary dateComponents=\"\(day)\" activeEnergyBurned=\"\(calories)\" activeEnergyBurnedUnit=\"\(unit)\"/>"
    }

    @Test func oneBadHealthDayIsSkippedInsteadOfCancellingTheImport() throws {
        let body = summary("2026-09-08", "450") + summary("2026-02-30", "300") + summary("2026-09-06", "nan")
            + summary("2026-09-05", "200") + summary("2026-09-05", "260")
        let report = try HealthActivityImporter.readXMLReport(export(body))
        #expect(report.entries.map(\.day) == ["2026-09-08"])
        #expect(report.skipped == 3)
    }

    @Test func healthCalUnitIsAKilocalorie() throws {
        let entries = try HealthActivityImporter.readXML(export(summary("2026-09-08", "512", unit: "Cal")))
        #expect(entries.first?.activeCalories == 512)
        #expect(throws: (any Error).self) { try HealthActivityImporter.readXML(export(summary("2026-09-08", "512", unit: "cal"))) }
    }

    @Test func healthXMLFileIsStreamedFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xml")
        defer { try? FileManager.default.removeItem(at: url) }
        try export(summary("2026-09-08", "450")).write(to: url)
        #expect(try HealthActivityImporter.read(url: url).first?.activeCalories == 450)
    }

    @Test func downloadProgressSumsLayersAndNeverGoesBack() {
        func event(_ digest: String, _ completed: Double, _ total: Double) -> OllamaService.DownloadProgress {
            try! JSONDecoder().decode(OllamaService.DownloadProgress.self, from: Data(
                #"{"status":"pulling","digest":"\#(digest)","completed":\#(completed),"total":\#(total)}"#.utf8))
        }
        var tracker = OllamaService.DownloadTracker()
        let big = tracker.update(event("a", 900, 1000)) ?? 0
        let small = tracker.update(event("b", 0, 10)) ?? 0
        #expect(big == 0.9)
        #expect(small >= big)
        #expect(tracker.update(event("b", 10, 10)) ?? 0 > big)
    }

    @Test func modelDecodingErrorsAreReadable() {
        let envelope = Data(#"{"message":{"content":"{\"name\":1}"},"done":true}"#.utf8)
        do { _ = try DrinkEstimate.decode(envelope); Issue.record("Expected failure") }
        catch { #expect(error.localizedDescription.contains("Не удалось прочитать")) }
    }

    @Test func openAIDrinkAndPantryRequestsCarryPhotoSchemaAndNoStorage() throws {
        let request = try OpenAIService.makeStructuredRequest(
            instructions: DrinkEstimate.instructions, text: "Объём: 250 мл", jpeg: Data([1, 2, 3]),
            name: "drink_estimate", schema: DrinkEstimate.schema, key: "sk-test", model: "gpt-test")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["store"] as? Bool == false)
        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["name"] as? String == "drink_estimate")
        #expect(throws: (any Error).self) {
            try OpenAIService.makeStructuredRequest(instructions: "", text: "", jpeg: Data([1]), name: "x",
                                                    schema: [:], key: " ", model: "gpt-test")
        }
        let reply = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"items\":[\"Сыр\"],\"uncertainties\":[]}"}]}]}"#.utf8)
        #expect(try PantryInventory.validated(OpenAIService.outputText(reply)).items == ["Сыр"])
    }

    @Test func lockWaitsBrieflyForAnotherSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = directory.appendingPathComponent(".meals.lock")
        let held = DispatchSemaphore(value: 0)
        let thread = Thread {
            try? PrivateStorage.withExclusiveLock(at: lock) { held.signal(); usleep(200_000) }
        }
        thread.start()
        held.wait()
        // The other save finishes within the wait, so this one proceeds instead of reporting a conflict.
        #expect(try PrivateStorage.withExclusiveLock(at: lock) { true })
        #expect(throws: FoodError.self) {
            try PrivateStorage.withExclusiveLock(at: lock) {
                try PrivateStorage.withExclusiveLock(at: lock, wait: 0.1) { () }
            }
        }
    }

    @Test func futureDaysAreRejectedButAnyTimeTodayIsAllowed() {
        let calendar = Calendar.current
        let now = Date()
        let lateToday = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        #expect(Meal.allowsDate(lateToday, now: now))
        #expect(Meal.allowsDate(now.addingTimeInterval(-86400 * 30), now: now))
        #expect(!Meal.allowsDate(tomorrow, now: now))
    }

    @Test func snackSymbolIsNotTheAppleLogo() {
        #expect(MealKind.snack.symbol != "apple.logo")
    }
}
