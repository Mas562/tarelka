import Foundation

/// Reject overlapping inference rather than leaving invisible work in a queue.
actor LocalInferenceGate {
    static let shared = LocalInferenceGate()
    private var occupied = false
    func acquire() throws {
        try Task.checkCancellation()
        guard !occupied else { throw LocalModelError.busy }
        occupied = true
    }
    func release() { occupied = false }
}
