import Foundation
import Testing
@testable import NutritionCore

struct InferencePerformanceTests {
    @Test func coachUsesSmallCPUModelWithBoundedWorkAndUnloadsIt() throws {
        let context = CoachContext(date: Date(), meals: [], personal: PersonalData())
        let request = try OllamaService.makeCoachRequest(context: context, question: "Что съесть?")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let options = try #require(body["options"] as? [String: Any])
        #expect(body["model"] as? String == OllamaService.ModelRole.coach.name)
        #expect(body["model"] as? String != OllamaService.model)
        #expect(options["num_gpu"] as? Int == 0)
        #expect(options["num_thread"] as? Int == 2)
        #expect(options["num_ctx"] as? Int == 6144)
        #expect(options["num_batch"] as? Int == 32)
        #expect(options["num_predict"] as? Int == 1000)
        #expect(body["keep_alive"] as? Int == 0)
    }
    @Test func coachReadinessRejectsCloudAndWrongModel() throws {
        try OllamaService.validateModel(Data(#"{"capabilities":["completion"],"model_info":{"general.architecture":"qwen3"}}"#.utf8), role: .coach)
        for bad in [
            #"{"capabilities":["completion"],"remote_host":"https://example.com","model_info":{"general.architecture":"qwen3"}}"#,
            #"{"capabilities":["completion"],"model_info":{"general.architecture":"qwen3vl"}}"#,
            #"{"capabilities":[],"model_info":{"general.architecture":"qwen3"}}"#
        ] {
            #expect(throws: LocalModelError.invalidCoachModel) { try OllamaService.validateModel(Data(bad.utf8), role: .coach) }
        }
    }
    @Test func sharedGateRejectsOverlapsAndCanBeReused() async throws {
        let gate = LocalInferenceGate()
        try await gate.acquire()
        await #expect(throws: LocalModelError.busy) { try await gate.acquire() }
        await gate.release()
        try await gate.acquire()
        await gate.release()
        let task = Task {
            try await Task.sleep(for: .seconds(10))
            try await gate.acquire()
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await gate.acquire()
        await gate.release()
    }
}
