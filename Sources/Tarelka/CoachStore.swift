import SwiftUI
import NutritionCore

@MainActor
final class CoachStore: ObservableObject {
    @Published private(set) var advice: NutritionAdvice?
    @Published private(set) var context: CoachContext?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var answeredQuestion = ""
    private var task: Task<Void, Never>?
    private var token = UUID()
    private var recentAdvice: [String] = []
    private let historyURL: URL?
    typealias Advisor = @Sendable (CoachContext, String, [String]) async throws -> NutritionAdvice
    private let advisor: Advisor
    init(directory: URL? = nil, advisor: @escaping Advisor = { context, question, history in
        try await OllamaService().advise(context: context, question: question, recentAdvice: history)
    }) {
        self.advisor = advisor
        historyURL = directory?.appendingPathComponent("coach-history.json")
        if let historyURL, let bytes = try? Data(contentsOf: historyURL),
           let saved = try? JSONDecoder().decode([String].self, from: bytes) {
            recentAdvice = saved.suffix(4).map { String($0.prefix(650)) }
        }
    }
    func schedule(_ snapshot: CoachContext?, question: String = "", force: Bool = false) {
        // Legacy automatic callers must never start inference. Only an explicit
        // button press may ask the model; live nutrition totals need no model.
        guard force, let snapshot, !loading else { return }
        task?.cancel(); token = UUID()
        error = nil; loading = true
        let requestToken = token
        task = Task {
            do {
                let result = try await advisor(snapshot, question, recentAdvice)
                try Task.checkCancellation()
                guard token == requestToken else { return }
                context = snapshot; answeredQuestion = question
                advice = result; updatedAt = Date(); loading = false
                recentAdvice.append(String((result.next_meal + " " + result.swap).prefix(650)))
                recentAdvice = Array(recentAdvice.suffix(4))
                if let historyURL, let data = try? JSONEncoder().encode(recentAdvice) {
                    try? data.write(to: historyURL, options: .atomic)
                }
            } catch {
                guard token == requestToken else { return }
                loading = false
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { task?.cancel(); token = UUID(); loading = false }
}
