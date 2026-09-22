import Foundation

/// Speech may return only the newest utterance after a pause, while partial
/// results within one utterance are revisions, not text to append.
struct DictationTranscript {
    private var committed: [String] = []
    private var current = ""
    private var start: TimeInterval?
    private var end: TimeInterval?
    private var completed = false
    var text: String { String((committed + [current]).filter { !$0.isEmpty }.joined(separator: ", ").prefix(4000)) }

    mutating func update(_ text: String, start incomingStart: TimeInterval?, end incomingEnd: TimeInterval?, completed: Bool) {
        let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return }
        let startsLater: Bool
        if let incomingStart, let end, let start {
            startsLater = incomingStart > start + 0.1 && incomingStart >= end - 0.05
        } else { startsLater = false }
        // Some on-device versions reset the timestamps as well as the text.
        // Only use this fallback after a completed utterance, never on a partial correction.
        let resetsCompleted = self.completed && !current.isEmpty
            && !Self.words(next).hasPrefix(Self.words(current))
            && incomingStart.map { $0 < (self.end ?? 0) - 0.1 } == true
            && incomingStart.map { $0 <= 0.05 } == true
        if startsLater || resetsCompleted { finishUtterance() }
        current = next
        if let incomingStart, let incomingEnd, incomingEnd > incomingStart {
            start = incomingStart; end = incomingEnd
        }
        self.completed = completed
    }

    private static func words(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    mutating func finishUtterance() {
        if !current.isEmpty { committed.append(current) }
        current = ""; start = nil; end = nil; completed = false
    }
}
