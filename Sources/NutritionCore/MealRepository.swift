import Foundation
import Darwin

/// A versioned, atomic journal. An unreadable or newer file is surfaced and never reset.
/// A single damaged row does not block the diary: it is moved, unchanged, to `meals-unreadable.json`.
public struct MealRepository {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var journalURL: URL { directory.appendingPathComponent("meals.json") }
    public var photosURL: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
    public var unreadableURL: URL { directory.appendingPathComponent("meals-unreadable.json") }
    private var lockURL: URL { directory.appendingPathComponent(".meals.lock") }

    private struct Journal: Codable { var version = 1; let meals: [Meal] }
    private struct Header: Decodable { let version: Int? }

    public func load() throws -> [Meal] { try read().meals }

    /// Moves damaged rows out of the journal so the rest stays editable. Returns how many were moved.
    @discardableResult
    public func recoverUnreadable() throws -> Int {
        try PrivateStorage.withExclusiveLock(at: lockURL) {
            let stored = try read()
            guard !stored.unreadable.isEmpty else { return 0 }
            try preserve(stored.unreadable)
            try write(stored.meals)
            return stored.unreadable.count
        }
    }
    @discardableResult
    public func save(_ meals: [Meal], replacing baseline: [Meal]? = nil) throws -> [Meal] {
        for meal in meals { try meal.validate() }
        guard Set(meals.map(\.id)).count == meals.count else { throw FoodError.duplicateEntries }
        return try PrivateStorage.withExclusiveLock(at: lockURL) {
            var result = meals
            if let baseline {
                guard Set(baseline.map(\.id)).count == baseline.count else { throw FoodError.duplicateEntries }
                let before = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
                let proposed = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0) })
                let stored = try read()
                try preserve(stored.unreadable)
                var current = Dictionary(uniqueKeysWithValues: stored.meals.map { ($0.id, $0) })
                // Merge only this window's changes. Never resurrect a concurrently deleted row
                // or overwrite another editor's changes to the same row.
                for id in Set(before.keys).union(proposed.keys) where before[id] != proposed[id] {
                    guard current[id] == before[id] else { throw FoodError.storageConflict }
                    current[id] = proposed[id]
                }
                result = Array(current.values)
            } else if let stored = try? read() {
                try preserve(stored.unreadable)
            }
            return try write(result)
        }
    }

    @discardableResult
    private func write(_ meals: [Meal]) throws -> [Meal] {
        let result = meals.sorted { $0.date > $1.date }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateStorage.write(encoder.encode(Journal(version: result.contains(where: \.isDrink) ? 2 : 1, meals: result)), to: journalURL)
        return result
    }

    /// Valid rows, plus the raw bytes of rows that cannot be decoded, fail validation or repeat an ID.
    private func read() throws -> (meals: [Meal], unreadable: [Data]) {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return ([], []) }
        let data = try Data(contentsOf: journalURL)
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard (1...2).contains(header.version ?? 1) else { throw FoodError.storageVersion }
        if let journal = try? JSONDecoder().decode(Journal.self, from: data),
           (try? journal.meals.forEach { try $0.validate() }) != nil,
           Set(journal.meals.map(\.id)).count == journal.meals.count {
            return (journal.meals.sorted { $0.date > $1.date }, [])
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["meals"] as? [Any] else { throw FoodError.invalidResponse }
        var meals: [Meal] = [], unreadable: [Data] = [], ids = Set<UUID>()
        for row in rows {
            let raw = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .fragmentsAllowed])
            if let meal = try? JSONDecoder().decode(Meal.self, from: raw), (try? meal.validate()) != nil,
               ids.insert(meal.id).inserted {
                meals.append(meal)
            } else { unreadable.append(raw) }
        }
        return (meals.sorted { $0.date > $1.date }, unreadable)
    }

    /// Appends rows to the side file before they leave the journal. Never overwrites an unreadable side file.
    private func preserve(_ rows: [Data]) throws {
        guard !rows.isEmpty else { return }
        var kept: [Any] = []
        if FileManager.default.fileExists(atPath: unreadableURL.path) {
            guard let array = try JSONSerialization.jsonObject(with: Data(contentsOf: unreadableURL)) as? [Any]
            else { throw FoodError.invalidResponse }
            kept = array
        }
        let known = Set(kept.compactMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) })
        let added = rows.filter { !known.contains($0) }
            .compactMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        guard !added.isEmpty else { return }
        try PrivateStorage.write(JSONSerialization.data(withJSONObject: kept + added, options: [.prettyPrinted, .sortedKeys]),
                                 to: unreadableURL)
    }
    public func savePhoto(_ data: Data) throws -> String {
        try PrivateStorage.prepareDirectory(photosURL)
        let filename = UUID().uuidString + ".jpg"
        try PrivateStorage.write(data, to: photosURL.appendingPathComponent(filename))
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

/// The user's diary and profile may contain sensitive health information.
/// Restrict an existing directory before an atomic write creates its temporary file.
public enum PrivateStorage {
    /// A separate inode keeps the lock valid across atomic journal replacements.
    /// Do not block the main thread when another process is saving.
    public static func withExclusiveLock<T>(at url: URL, _ work: () throws -> T) throws -> T {
        try prepareDirectory(url.deletingLastPathComponent())
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { throw FoodError.storageConflict }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { flock(descriptor, LOCK_UN) }
        return try work()
    }

    public static func prepareDirectory(_ directory: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    public static func write(_ data: Data, to url: URL) throws {
        try prepareDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Tighten permissions on files created by older versions, without changing their contents.
    public static func secureExisting(in directory: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        for name in ["meals.json", "meals-unreadable.json", "personal.json", "reminders.json", "coach-history.json"] {
            let url = directory.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) {
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
        let photos = directory.appendingPathComponent("Photos", isDirectory: true)
        if manager.fileExists(atPath: photos.path) {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: photos.path)
        }
    }
}
