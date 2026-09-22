import AppKit
import SwiftUI
import NutritionCore

enum DrinkPhotoChange {
    case unchanged, replace(Data), remove
}

@MainActor
final class DrinkPhotoStore: ObservableObject {
    @Published private(set) var preview: NSImage?
    @Published private(set) var data: Data?
    @Published private(set) var busy = false
    @Published var error: String?
    private(set) var change = DrinkPhotoChange.unchanged
    var removed: Bool { if case .remove = change { return true }; return false }
    private var task: Task<Void, Never>?
    private var token = UUID()

    func load(_ url: URL, replacing: Bool = true) {
        cancel(); busy = true; error = nil
        let request = token
        task = Task {
            do {
                let bytes = try await Task.detached(priority: .userInitiated) { try PhotoLoader.load(url: url) }.value
                try Task.checkCancellation()
                guard request == token else { return }
                data = bytes; preview = NSImage(data: bytes)
                if replacing { change = .replace(bytes) }
            } catch {
                guard request == token, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            if request == token { busy = false }
        }
    }
    func remove() {
        cancel(); data = nil; preview = nil; change = .remove; error = nil
    }
    func cancel() { task?.cancel(); task = nil; token = UUID(); busy = false }
}
