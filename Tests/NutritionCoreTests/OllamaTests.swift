import Foundation
import Testing
@testable import NutritionCore

private let localFoodJSON = #"{"is_food":true,"dish_name":"Порция","ingredients":[{"name":"Продукт","estimated_grams":100,"calories_per_100g":200,"protein_per_100g":10,"fat_per_100g":8,"carbs_per_100g":22}],"assumptions":["Тест"]}"#

private func localResponse(done: Bool = true, reason: String = "stop", food: String = localFoodJSON) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["done": done, "done_reason": reason, "message": ["content": food]])
}

private class LocalSuccessProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "127.0.0.1", request.value(forHTTPHeaderField: "Authorization") == nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = request.url?.path == "/api/show"
            ? Data(#"{"capabilities":["completion","vision"],"model_info":{"general.architecture":"qwen3vl","block_count":34,"tokens":null}}"#.utf8)
            : try! localResponse()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class MissingLocalModelProtocol: LocalSuccessProtocol, @unchecked Sendable {
    override func startLoading() {
        guard request.url?.path == "/api/show" else {
            Issue.record("A photo request was sent despite the missing local model")
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"model missing"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct OllamaTests {
    private func session(_ type: URLProtocol.Type) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [type]
        return URLSession(configuration: config)
    }
    @Test func freeProviderIsDefaultForNewAndExistingInstalls() {
        #expect(RecognitionProvider.restored(nil) == .local)
        #expect(RecognitionProvider.restored("unexpected") == .local)
        #expect(RecognitionProvider.restored("openAI") == .openAI)
    }
    @Test func photoRequestUsesOnlyLocalFixedModelWithoutKey() throws {
        let request = try OllamaService.makeRequest(jpeg: Data([1, 2, 3]), weight: 350.5, notes: "Рис")
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "qwen3-vl:8b-instruct")
        #expect(body["keep_alive"] as? Int == 0)
        #expect(body["think"] == nil)
        let options = try #require(body["options"] as? [String: Any])
        #expect(options["num_ctx"] as? Int == 8192)
        #expect(options["presence_penalty"] as? Double == 1.5)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.last?["images"] as? [String] == ["AQID"])
        #expect(throws: (any Error).self) { try OllamaService.makeRequest(jpeg: data, weight: 0, notes: "") }
    }
    @Test func rejectsCloudAndNonVisionModelMetadata() throws {
        try OllamaService.validateModel(Data(#"{"capabilities":["vision"],"model_info":{"general.architecture":"qwen3vl","some_array":[1,2]}}"#.utf8))
        for invalid in [
            #"{"capabilities":["vision"],"remote_model":"qwen3-vl:cloud","model_info":{"general.architecture":"qwen3vl"}}"#,
            #"{"capabilities":["vision"],"remote_host":"https://example.com","model_info":{"general.architecture":"qwen3vl"}}"#,
            #"{"capabilities":["completion"],"model_info":{"general.architecture":"qwen3vl"}}"#,
            #"{"capabilities":["vision"],"model_info":{"general.architecture":"gemma3"}}"#,
            #"{"capabilities":["vision"],"model_info":{"general.architecture":"unknown"}}"#
        ] {
            #expect(throws: LocalModelError.invalidModel) { try OllamaService.validateModel(Data(invalid.utf8)) }
        }
    }
    @Test func localRoundTripNormalizesMeasuredWeight() async throws {
        let session = session(LocalSuccessProtocol.self)
        defer { session.invalidateAndCancel() }
        let estimate = try await OllamaService(session: session).analyze(jpeg: Data([1, 2]), weight: 350.5, notes: "")
        let ingredients = try estimate.normalizedIngredients(weight: 350.5)
        #expect(ingredients.first?.grams == 350.5)
        #expect(NutritionMath.total(ingredients).calories == 701)
    }
    @Test func missingModelStopsBeforeSendingPhoto() async throws {
        let session = session(MissingLocalModelProtocol.self)
        defer { session.invalidateAndCancel() }
        await #expect(throws: LocalModelError.missingModel) {
            try await OllamaService(session: session).analyze(jpeg: Data([1]), weight: 350, notes: "")
        }
    }
    @Test func rejectsUnfinishedNonFoodAndInvalidNutritionResponses() throws {
        #expect(throws: LocalModelError.incomplete) { try OllamaService.decodeResponse(localResponse(done: false), weight: 350) }
        #expect(throws: LocalModelError.incomplete) { try OllamaService.decodeResponse(localResponse(reason: "length"), weight: 350) }
        for text in ["oops", localFoodJSON.replacingOccurrences(of: "true", with: "false"),
                     localFoodJSON.replacingOccurrences(of: "\"calories_per_100g\":200", with: "\"calories_per_100g\":-1")] {
            #expect(throws: (any Error).self) { try OllamaService.decodeResponse(localResponse(food: text), weight: 350) }
        }
    }
    @Test func localSessionRejectsExternalRedirect() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://example.com/photo")!)
        let response = HTTPURLResponse(url: URL(string: "http://127.0.0.1:11434/api/chat")!, statusCode: 307, httpVersion: nil, headerFields: nil)!
        LocalOnlySessionDelegate().urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: response, newRequest: request) { redirected in
            #expect(redirected == nil)
        }
    }
}
