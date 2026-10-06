import Foundation

public struct OpenAIService: Sendable {
    public static let defaultModel = "gpt-5.4-mini"
    private let session: URLSession
    private static let defaultSession = URLSession(configuration: .ephemeral,
                                                    delegate: NoRedirectSessionDelegate(), delegateQueue: nil)
    public init(session: URLSession? = nil) { self.session = session ?? Self.defaultSession }

    public func analyze(jpeg: Data, weight: Double, notes: String, key: String,
                        model: String = defaultModel) async throws -> FoodEstimate {
        let request = try Self.makeRequest(jpeg: jpeg, weight: weight, notes: notes, key: key, model: model)
        return try Self.decodeResponse(await send(request), weight: weight)
    }
    /// Drink photos follow the recognition provider chosen in Settings, like meal photos.
    public func analyzeDrink(jpeg: Data, volume: Double, notes: String, key: String,
                             model: String = defaultModel) async throws -> DrinkEstimate {
        guard Numbers.validWeight(volume) else { throw FoodError.invalidWeight }
        let request = try Self.makeStructuredRequest(
            instructions: DrinkEstimate.instructions, text: "Объём: \(volume) мл. Название и добавки: \(notes.prefix(1500))",
            jpeg: jpeg, name: "drink_estimate", schema: DrinkEstimate.schema, key: key, model: model)
        return try DrinkEstimate.validated(Self.outputText(await send(request)))
    }
    public func pantry(jpeg: Data, key: String, model: String = defaultModel) async throws -> PantryInventory {
        let request = try Self.makeStructuredRequest(
            instructions: PantryInventory.instructions, text: "Какие продукты видны?",
            jpeg: jpeg, name: "pantry_inventory", schema: PantryInventory.schema, key: key, model: model)
        return try PantryInventory.validated(Self.outputText(await send(request)))
    }
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw FoodError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw FoodError.unauthorized
        case 429: throw FoodError.rateLimited
        default: throw FoodError.requestFailed(http.statusCode)
        }
    }
    /// The app validates every reply itself, so these schemas may use bounds that strict mode does not accept.
    static func makeStructuredRequest(instructions: String, text: String, jpeg: Data, name: String,
                                      schema: [String: Any], key: String, model: String) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FoodError.unauthorized }
        guard !jpeg.isEmpty else { throw FoodError.invalidResponse }
        return try request(key: key, payload: [
            "model": model, "store": false, "max_output_tokens": 3000, "instructions": instructions,
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": text],
                ["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())", "detail": "high"]
            ]]],
            "text": ["format": ["type": "json_schema", "name": name, "strict": false, "schema": schema]]
        ])
    }

    public static func makeRequest(jpeg: Data, weight: Double, notes: String, key: String,
                                   model: String) throws -> URLRequest {
        guard Numbers.validWeight(weight) else { throw FoodError.invalidWeight }
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FoodError.unauthorized }
        guard !jpeg.isEmpty else { throw FoodError.invalidResponse }
        let payload: [String: Any] = [
            "model": model, "store": false, "max_output_tokens": 6000,
            "instructions": FoodRecognitionFormat.instructions,
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": "Вес готовой еды: \(weight) г. Уточнения пользователя: \(notes.prefix(8000))"],
                ["type": "input_image", "image_url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())", "detail": "high"]
            ]]],
            "text": ["format": ["type": "json_schema", "name": "meal_estimate", "strict": true, "schema": FoodRecognitionFormat.schema]]
        ]
        return try request(key: key, payload: payload)
    }
    private static func request(key: String, payload: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    public static func decodeResponse(_ data: Data, weight: Double) throws -> FoodEstimate {
        let json = try outputText(data)
        let estimate: FoodEstimate
        do { estimate = try JSONDecoder().decode(FoodEstimate.self, from: json) }
        catch { throw FoodError.invalidResponse }
        _ = try estimate.normalizedIngredients(weight: weight)
        return estimate
    }
    /// The model's JSON text from a Responses API reply.
    static func outputText(_ data: Data) throws -> Data {
        struct Envelope: Decodable {
            struct Output: Decodable {
                struct Content: Decodable { let type: String; let text: String? }
                let type: String
                let content: [Content]?
            }
            let status: String
            let output: [Output]
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw FoodError.invalidResponse }
        guard envelope.status == "completed" else { throw FoodError.incomplete }
        let parts = envelope.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        guard !parts.contains(where: { $0.type == "refusal" }) else { throw FoodError.refused }
        let text = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard let json = text.data(using: .utf8), !json.isEmpty else { throw FoodError.invalidResponse }
        return json
    }
}
