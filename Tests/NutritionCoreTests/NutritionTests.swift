import Foundation
import Testing
@testable import NutritionCore

struct NutritionTests {
    private func food(_ grams: Double = 100) -> Ingredient {
        Ingredient(name: "Тестовый продукт", grams: grams, per100: Nutrients(calories: 200, protein: 10, fat: 8, carbs: 22))
    }
    @Test func testRussianInputAndMalformedValues() {
        #expect((Numbers.parse(" 350,5 ")) == (350.5))
        #expect((Numbers.parse("350.5")) == (350.5))
        for value in ["", "-1", "NaN", "inf", "3,5.2", "350 г", "1e9", "1 000"] {
            #expect((Numbers.parse(value)) == nil)
        }
        #expect(!(Numbers.validWeight(0)))
        #expect(!(Numbers.validWeight(.infinity)))
        #expect(!(Numbers.validWeight(20_001)))
        #expect(Numbers.validWeight(0.1))
    }
    @Test func testInputFormattingPreservesIntegers() {
        for value in [0.0, 10, 100, 350.5, 0.001, 999.999] {
            #expect((Numbers.parse(Numbers.input(value))) == (value))
        }
    }
    @Test func testPortionUsesPer100Values() {
        let total = NutritionMath.total([food(350)])
        #expect(abs((total.calories) - (700)) <= 0.0001)
        #expect(abs((total.protein) - (35)) <= 0.0001)
        #expect(abs((total.fat) - (28)) <= 0.0001)
        #expect(abs((total.carbs) - (77)) <= 0.0001)
    }
    @Test func testNormalizationUsesMeasuredWeightAndPreservesRatio() throws {
        let ingredients = try NutritionMath.normalize([food(200), food(100)], to: 450)
        #expect(abs((ingredients[0].grams) - (300)) <= 0.0001)
        #expect(abs((ingredients[1].grams) - (150)) <= 0.0001)
        #expect(abs((NutritionMath.total(ingredients).calories) - (900)) <= 0.0001)
        #expect((ingredients[0].per100) == (food().per100))
        try NutritionMath.validate(ingredients, weight: 450)
        #expect(throws: (any Error).self) { try NutritionMath.validate(ingredients, weight: 350) }
    }
    @Test func testInvalidNutritionCannotBeSavedOrNormalized() {
        var ingredient = food()
        ingredient.per100.fat = -1
        #expect(!(ingredient.isValid))
        #expect(throws: (any Error).self) { try NutritionMath.normalize([ingredient], to: 350) }
        ingredient.per100.fat = 101
        #expect(!(ingredient.isValid))
        ingredient.per100.fat = 80
        #expect(!(ingredient.isValid))
        ingredient = food(); ingredient.grams = .nan
        #expect(!(ingredient.isValid))
        #expect(throws: (any Error).self) { try NutritionMath.normalize([], to: 100) }
    }
    @Test func testPersistenceRoundTripAndCorruptionIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MealRepository(directory: directory)
        #expect((try repository.load()) == ([]))
        let meal = Meal(date: Date(timeIntervalSince1970: 1000), kind: .lunch, name: "Порция", weight: 250, ingredients: [food(250)])
        try repository.save([meal])
        #expect((try repository.load()) == ([meal]))
        let invalidData = Data("broken journal".utf8)
        try invalidData.write(to: repository.journalURL)
        #expect(throws: (any Error).self) { try repository.load() }
        #expect((try Data(contentsOf: repository.journalURL)) == (invalidData))
    }
    @Test func testPhotoPathsRejectTraversalAndForeignFilenames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MealRepository(directory: directory)
        #expect((repository.photoURL("../../secret.jpg")) == nil)
        #expect((repository.photoURL("random.jpg")) == nil)
        #expect((repository.photoURL("/tmp/file.jpg")) == nil)
        let name = try repository.savePhoto(Data([1, 2, 3]))
        #expect((repository.photoURL(name)) != nil)
        #expect((try Data(contentsOf: #require(repository.photoURL(name)))) == (Data([1, 2, 3])))
        repository.removePhoto(name)
        #expect(!(FileManager.default.fileExists(atPath: try #require(repository.photoURL(name)).path)))
    }
    @Test func testRequestUsesResponsesImageAndStrictSchema() throws {
        let request = try OpenAIService.makeRequest(jpeg: Data([1, 2, 3]), weight: 350,
                                                    notes: "Курица с рисом", key: "test-key", model: "test-model")
        #expect((request.url?.absoluteString) == ("https://api.openai.com/v1/responses"))
        #expect((request.value(forHTTPHeaderField: "Authorization")) == ("Bearer test-key"))
        let requestBody = try #require(request.httpBody)
        let decodedBody = try JSONSerialization.jsonObject(with: requestBody)
        let object = try #require(decodedBody as? [String: Any])
        #expect((object["store"] as? Bool) == (false))
        #expect((object["model"] as? String) == ("test-model"))
        let text = try #require(object["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect((format["strict"] as? Bool) == (true))
        #expect((format["type"] as? String) == ("json_schema"))
        let input = try #require(object["input"] as? [[String: Any]])
        let content = try #require(input.first?["content"] as? [[String: Any]])
        #expect((content.last?["type"] as? String) == ("input_image"))
        #expect((content.last?["image_url"] as? String) == ("data:image/jpeg;base64,AQID"))
    }
    private func response(food: Bool = true, calories: Double = 200, status: String = "completed") throws -> Data {
        let body: [String: Any] = ["is_food": food, "dish_name": "Порция", "assumptions": ["Тест"], "ingredients": [[
            "name": "Продукт", "estimated_grams": 100, "calories_per_100g": calories,
            "protein_per_100g": 10, "fat_per_100g": 8, "carbs_per_100g": 22
        ]]]
        let string = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
        return try JSONSerialization.data(withJSONObject: ["status": status, "output": [
            ["type": "reasoning"], ["type": "message", "content": [["type": "output_text", "text": string]]]
        ]])
    }
    @Test func testParsesMessageAfterReasoningAndNormalizes() throws {
        let estimate = try OpenAIService.decodeResponse(response(), weight: 350)
        #expect((estimate.dish_name) == ("Порция"))
        #expect((try estimate.normalizedIngredients(weight: 350).first?.grams) == (350))
    }
    @Test func testRejectsNonFoodIncompleteRefusalAndInvalidValues() throws {
        #expect(throws: (any Error).self) { try OpenAIService.decodeResponse(response(food: false), weight: 350) }
        #expect(throws: (any Error).self) { try OpenAIService.decodeResponse(response(calories: -1), weight: 350) }
        #expect(throws: (any Error).self) { try OpenAIService.decodeResponse(response(status: "incomplete"), weight: 350) }
        let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}"#.utf8)
        #expect(throws: (any Error).self) { try OpenAIService.decodeResponse(refusal, weight: 350) }
        #expect(throws: (any Error).self) { try OpenAIService.decodeResponse(Data("oops".utf8), weight: 350) }
    }
}
