import Foundation

public struct DrinkEstimate: Decodable, Equatable, Sendable {
    public let name: String
    public let per100ml: Nutrients
    public let assumptions: [String]
    public static var schema: [String: Any] {
        ["type": "object", "additionalProperties": false, "required": ["name", "per100ml", "assumptions"],
         "properties": [
            "name": ["type": "string", "minLength": 1, "maxLength": 100],
            "per100ml": ["type": "object", "additionalProperties": false,
                         "required": ["calories", "protein", "fat", "carbs"],
                         "properties": ["calories", "protein", "fat", "carbs"].reduce(into: [String: Any]()) {
                             $0[$1] = ["type": "number", "minimum": 0, "maximum": $1 == "calories" ? 900 : 100]
                         }],
            "assumptions": ["type": "array", "maxItems": 4, "items": ["type": "string", "maxLength": 200]]
         ]]
    }
    public static func decode(_ data: Data) throws -> Self {
        struct Envelope: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
            let done: Bool
            let done_reason: String?
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.done, envelope.done_reason != "length" else { throw LocalModelError.incomplete }
        let value = try JSONDecoder().decode(Self.self, from: Data(envelope.message.content.utf8))
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.name.count <= 100,
              value.per100ml.isValidPer100, value.assumptions.count <= 4,
              value.assumptions.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { throw FoodError.invalidResponse }
        return value
    }
}
