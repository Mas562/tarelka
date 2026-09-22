import Foundation

public struct OpenAIService: Sendable {
    public static let defaultModel = "gpt-5.4-mini"
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func analyze(jpeg: Data, weight: Double, notes: String, key: String,
                        model: String = defaultModel) async throws -> FoodEstimate {
        let request = try Self.makeRequest(jpeg: jpeg, weight: weight, notes: notes, key: key, model: model)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw FoodError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw FoodError.unauthorized
        case 429: throw FoodError.rateLimited
        default: throw FoodError.requestFailed(http.statusCode)
        }
        return try Self.decodeResponse(data, weight: weight)
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
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    public static func decodeResponse(_ data: Data, weight: Double) throws -> FoodEstimate {
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
        guard let json = text.data(using: .utf8) else { throw FoodError.invalidResponse }
        let estimate: FoodEstimate
        do { estimate = try JSONDecoder().decode(FoodEstimate.self, from: json) }
        catch { throw FoodError.invalidResponse }
        _ = try estimate.normalizedIngredients(weight: weight)
        return estimate
    }
}
