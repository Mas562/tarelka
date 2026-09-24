import Foundation
import Darwin

/// A compact daily balance calculated from the same journal and profile as the main app.
public struct TodaySnapshot: Codable, Equatable, Sendable {
    public let day: String
    public let eaten: Nutrients
    public let target: Double?
    public let remaining: Double?
    public let macroTargets: MacroTargets?
    public let activity: Double?
    public let entryCount: Int

    public init(date: Date, meals: [Meal], personal: PersonalData, timeZone: TimeZone = .current) {
        let dayKey = DayKey.string(date, timeZone: timeZone)
        day = dayKey
        let today = meals.filter { DayKey.string($0.date, timeZone: timeZone) == dayKey }
        eaten = today.reduce(Nutrients()) { $0 + $1.total }
        let budget = personal.budget(on: date, eaten: eaten.calories, timeZone: timeZone)
        target = budget?.target
        remaining = budget?.remaining
        macroTargets = budget?.macroTargets
        activity = budget?.creditsActivity == true ? budget?.active : nil
        entryCount = today.count
    }
}

public enum TodaySnapshotStore {
    public static let widgetKind = "TarelkaToday"

    public static func load(on date: Date = Date(), directory: URL? = nil,
                            fileManager: FileManager = .default) -> TodaySnapshot? {
        // A WidgetKit extension has its own sandbox home. Resolve the account home
        // and read only the two journal files allowed by Widget.entitlements.
        guard let directory = directory ?? accountDirectory,
              (fileManager.fileExists(atPath: directory.appendingPathComponent("meals.json").path)
               || fileManager.fileExists(atPath: directory.appendingPathComponent("personal.json").path)),
              let meals = try? MealRepository(directory: directory).load(),
              let personal = try? PersonalRepository(directory: directory).load() else { return nil }
        return TodaySnapshot(date: date, meals: meals, personal: personal)
    }

    private static var accountDirectory: URL? {
        guard let account = getpwuid(getuid()) else { return nil }
        return URL(fileURLWithPath: String(cString: account.pointee.pw_dir), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Tarelka", isDirectory: true)
    }
}
