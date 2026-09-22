import Foundation

/// A versioned, atomic journal. Decode failures are surfaced; existing data is never silently reset.
public struct MealRepository {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var journalURL: URL { directory.appendingPathComponent("meals.json") }
    public var photosURL: URL { directory.appendingPathComponent("Photos", isDirectory: true) }

    private struct Journal: Codable { var version = 1; let meals: [Meal] }

    public func load() throws -> [Meal] {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return [] }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard (1...2).contains(journal.version) else { throw FoodError.storageVersion }
        for meal in journal.meals { try meal.validate() }
        guard Set(journal.meals.map(\.id)).count == journal.meals.count else { throw FoodError.invalidResponse }
        return journal.meals.sorted { $0.date > $1.date }
    }
    public func save(_ meals: [Meal]) throws {
        for meal in meals { try meal.validate() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Journal(version: meals.contains(where: \.isDrink) ? 2 : 1, meals: meals)).write(to: journalURL, options: .atomic)
    }
    public func savePhoto(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: photosURL, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let filename = UUID().uuidString + ".jpg"
        try data.write(to: photosURL.appendingPathComponent(filename), options: .atomic)
        return filename
    }
    public func photoURL(_ filename: String?) -> URL? {
        guard let filename, filename == (filename as NSString).lastPathComponent,
              filename.hasSuffix(".jpg"), UUID(uuidString: String(filename.dropLast(4))) != nil else { return nil }
        return photosURL.appendingPathComponent(filename)
    }
    public func removePhoto(_ filename: String?) {
        guard let url = photoURL(filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
