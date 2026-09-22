import Foundation

public struct PantryInventory: Codable, Equatable, Sendable {
    public let items: [String]
    public let uncertainties: [String]
    public static var schema: [String: Any] {
        ["type": "object", "additionalProperties": false, "required": ["items", "uncertainties"], "properties": [
            "items": ["type": "array", "maxItems": 35, "items": ["type": "string"]],
            "uncertainties": ["type": "array", "maxItems": 5, "items": ["type": "string"]]
        ]]
    }
    public static func decode(_ data: Data) throws -> Self {
        let value: Self = try LocalJSONResponse.decode(data)
        guard value.items.count <= 35, value.uncertainties.count <= 5,
              (value.items + value.uncertainties).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 }) else { throw FoodError.invalidResponse }
        return value
    }
}
public struct PantryRecipe: Codable, Equatable, Sendable {
    public let title: String
    public let servings: Int
    public let minutes: Int
    public let ingredients: [String]
    public let steps: [String]
    public let missing: [String]
    public let note: String
    public var isValid: Bool {
        (1...12).contains(servings) && (1...360).contains(minutes) && !title.isEmpty && title.count <= 150
        && (1...20).contains(ingredients.count) && (1...12).contains(steps.count) && missing.count <= 10 && note.count <= 1000
        && (ingredients + steps + missing).allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1000 }
    }
}
public struct PantryRecipes: Codable, Equatable, Sendable {
    public let recipes: [PantryRecipe]
    public static var schema: [String: Any] {
        let list: [String: Any] = ["type": "array", "maxItems": 20, "items": ["type": "string"]]
        let properties: [String: Any] = ["title": ["type": "string"], "servings": ["type": "integer", "minimum": 1, "maximum": 12],
            "minutes": ["type": "integer", "minimum": 1, "maximum": 360], "ingredients": list,
            "steps": ["type": "array", "maxItems": 12, "items": ["type": "string"]],
            "missing": ["type": "array", "maxItems": 10, "items": ["type": "string"]], "note": ["type": "string"]]
        return ["type": "object", "additionalProperties": false, "required": ["recipes"], "properties": [
            "recipes": ["type": "array", "minItems": 1, "maxItems": 3, "items": ["type": "object", "additionalProperties": false,
                "properties": properties, "required": properties.keys.sorted()]]
        ]]
    }
    public static func decode(_ data: Data) throws -> Self {
        let value: Self = try LocalJSONResponse.decode(data)
        guard (1...3).contains(value.recipes.count), value.recipes.allSatisfy(\.isValid) else { throw FoodError.invalidResponse }
        return value
    }
}
private enum LocalJSONResponse {
    private struct Envelope: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
            let done: Bool
            let done_reason: String?
        }
    static func decode<T: Decodable>(_ data: Data) throws -> T {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw FoodError.invalidResponse }
        guard envelope.done, envelope.done_reason != "length" else { throw LocalModelError.incomplete }
        guard let result = try? JSONDecoder().decode(T.self, from: Data(envelope.message.content.utf8)) else { throw FoodError.invalidResponse }
        return result
    }
}
