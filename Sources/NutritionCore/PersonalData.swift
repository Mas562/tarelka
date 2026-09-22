import Foundation

public struct SavedProduct: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var per100: Nutrients
    public var source: NutritionSource?
    public var caloriesFromMacros: Bool
    private var portionUnit: PortionUnit?
    public var unit: PortionUnit { portionUnit ?? .grams }
    public init(id: UUID = UUID(), name: String, per100: Nutrients, caloriesFromMacros: Bool = false, unit: PortionUnit = .grams, source: NutritionSource? = nil) {
        self.source = source
        self.id = id; self.name = name; self.per100 = per100; self.caloriesFromMacros = caloriesFromMacros
        portionUnit = unit == .grams ? nil : unit
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 300 && per100.isValidPer100
    }
    public func portion(amount: Double) -> Ingredient {
        var value = Ingredient(name: name, amount: amount, unit: unit, per100: per100)
        if source?.per100 == per100 { value.source = source }
        return value
    }
    public func portion(grams: Double) -> Ingredient { portion(amount: grams) }
}

public enum FormulaSex: String, Codable, CaseIterable, Sendable {
    case female = "Женский", male = "Мужской"
}
public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case low = "Мало движения", light = "Лёгкая активность", moderate = "Средняя активность", high = "Высокая активность"
    public var factor: Double {
        switch self { case .low: 1.2; case .light: 1.375; case .moderate: 1.55; case .high: 1.725 }
    }
    public var detail: String {
        switch self {
        case .low: "В основном сидячий день, без регулярных тренировок"
        case .light: "Немного движения и лёгкие тренировки 1–3 раза в неделю"
        case .moderate: "Регулярное движение и тренировки 3–5 раз в неделю"
        case .high: "Много движения и интенсивные тренировки почти каждый день"
        }
    }
}
public struct CalorieProfile: Codable, Equatable, Sendable {
    public var height: Double
    public var weight: Double
    public var age: Int
    public var sex: FormulaSex
    public var activity: ActivityLevel
    public init(height: Double, weight: Double, age: Int, sex: FormulaSex, activity: ActivityLevel) {
        self.height = height; self.weight = weight; self.age = age; self.sex = sex; self.activity = activity
    }
    public var isValid: Bool {
        height.isFinite && (100...250).contains(height) && weight.isFinite && (25...350).contains(weight) && (18...120).contains(age)
    }
    /// Mifflin–St Jeor predicts resting expenditure; the activity multiplier estimates maintenance.
    public var restingCalories: Double? {
        guard isValid else { return nil }
        return 10 * weight + 6.25 * height - 5 * Double(age) + (sex == .male ? 5 : -161)
    }
    public var maintenanceCalories: Double? { restingCalories.map { ($0 * activity.factor).rounded() } }
}

public enum ActivitySource: String, Codable, Sendable {
    case appleHealth = "Apple Здоровье", transferFile = "Файл с iPhone", manual = "Введено вручную"
}
public struct DailyActivity: Codable, Equatable, Sendable, Identifiable {
    public var day: String
    public var activeCalories: Double
    public var updatedAt: Date
    public var source: ActivitySource
    public var id: String { day }
    public init(day: String, activeCalories: Double, updatedAt: Date, source: ActivitySource) {
        self.day = day; self.activeCalories = activeCalories; self.updatedAt = updatedAt; self.source = source
    }
    public var isValid: Bool {
        DayKey.isValid(day) && activeCalories.isFinite && (0...30_000).contains(activeCalories)
        && updatedAt.timeIntervalSince1970.isFinite
    }
}
public enum DayKey {
    public static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = formatter(timeZone: timeZone)
        return formatter.string(from: date)
    }
    public static func isValid(_ string: String) -> Bool {
        guard string.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let formatter = formatter(timeZone: TimeZone(secondsFromGMT: 0)!)
        guard let date = formatter.date(from: string) else { return false }
        return formatter.string(from: date) == string
    }
    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter
    }
}
public enum DailyBudget {
    public static func remaining(target: Double, eaten: Double, activeCalories: Double = 0) -> Double {
        target + activeCalories - eaten
    }
}

public enum ActivityAccounting: String, Codable, CaseIterable, Sendable {
    case watch = "Покой + Apple Watch"
    case estimated = "Обычная активность"
    public var detail: String {
        self == .watch ? "Расход в покое + активные калории за выбранный день. Коэффициент активности не используется."
        : "Расход в покое × коэффициент активности. Калории часов показаны отдельно и повторно не прибавляются."
    }
}
public enum NutritionGoal: String, Codable, CaseIterable, Sendable {
    case maintain = "Поддерживать вес", gentleLoss = "Плавно снижать вес"
}
public struct BudgetSettings: Codable, Equatable, Sendable {
    public var accounting: ActivityAccounting
    public var goal: NutritionGoal
    public init(accounting: ActivityAccounting = .watch, goal: NutritionGoal = .maintain) {
        self.accounting = accounting; self.goal = goal
    }
}
public struct DayBudget: Equatable, Sendable {
    public let base: Double
    public let active: Double?
    public let creditsActivity: Bool
    public let deficit: Double
    public let eaten: Double
    public var creditedActivity: Double { creditsActivity ? (active ?? 0) : 0 }
    public var target: Double { base + creditedActivity - deficit }
    public var remaining: Double { target - eaten }
    public var netEaten: Double { eaten - creditedActivity }
    public var awaitingActivity: Bool { creditsActivity && active == nil }
}

public struct PersonalData: Codable, Equatable, Sendable {
    public var version = 1
    public var products: [SavedProduct] = []
    public var profile: CalorieProfile?
    public var manualTarget: Double?
    public var activity: [DailyActivity] = []
    public var linkedFileBookmark: Data?
    public var linkedFileName: String?
    // Optional additions preserve decoding of diaries saved by versions 1.0–1.2.
    public var budgetSettings: BudgetSettings?
    public var coachEnabled: Bool?
    public var dietaryNotes: String?
    public init() {}
    public var settings: BudgetSettings { budgetSettings ?? BudgetSettings() }
    public var dailyTarget: Double? {
        manualTarget ?? (settings.accounting == .watch ? profile?.restingCalories?.rounded() : profile?.maintenanceCalories)
    }
    public func budget(on date: Date, eaten: Double, timeZone: TimeZone = .current) -> DayBudget? {
        guard let base = dailyTarget, base.isFinite, base > 0, eaten.isFinite, eaten >= 0 else { return nil }
        let day = DayKey.string(date, timeZone: timeZone)
        let active = activity.first { $0.day == day }?.activeCalories
        let adds = settings.accounting == .watch
        let maintenance = base + (adds ? (active ?? 0) : 0)
        var deficit = 0.0
        // A manually supplied target is already the user's goal. Never subtract a second deficit.
        if settings.goal == .gentleLoss, manualTarget == nil, let profile,
           profile.weight / pow(profile.height / 100, 2) >= 18.5 {
            let floor = profile.sex == .male ? 1500.0 : 1200.0
            deficit = max(0, min(300, maintenance * 0.1, maintenance - floor)).rounded()
        }
        return DayBudget(base: base, active: active, creditsActivity: adds, deficit: deficit, eaten: eaten)
    }
    public func validate() throws {
        guard (1...2).contains(version) else { throw FoodError.storageVersion }
        guard products.allSatisfy(\.isValid), Set(products.map(\.id)).count == products.count,
              profile?.isValid != false,
              manualTarget.map({ $0.isFinite && (500...10_000).contains($0) }) ?? true,
              (dietaryNotes?.count ?? 0) <= 1000,
              activity.allSatisfy(\.isValid), Set(activity.map(\.day)).count == activity.count else { throw PersonalError.invalidData }
    }
    public mutating func mergeActivity(_ incoming: [DailyActivity]) throws {
        guard incoming.allSatisfy(\.isValid), Set(incoming.map(\.day)).count == incoming.count else { throw PersonalError.invalidActivity }
        var byDay = Dictionary(uniqueKeysWithValues: activity.map { ($0.day, $0) })
        for item in incoming {
            if let previous = byDay[item.day], previous.updatedAt > item.updatedAt { continue }
            byDay[item.day] = item
        }
        activity = byDay.values.sorted { $0.day > $1.day }
    }
}
public enum PersonalError: LocalizedError {
    case invalidData, invalidActivity, noActivity, invalidFormat
    public var errorDescription: String? {
        switch self {
        case .invalidData: "Проверьте данные продуктов, профиля и дневной нормы."
        case .invalidActivity: "В файле неверные или противоречивые данные активности. Существующие записи сохранены."
        case .noActivity: "В файле нет дневных итогов активности Apple Watch. Убедитесь, что часы синхронизировались с iPhone, и повторите экспорт."
        case .invalidFormat: "Выберите export.xml из экспорта «Здоровья» или JSON-файл активности в формате «Тарелки»."
        }
    }
}

public struct PersonalRepository {
    public let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("personal.json") }
    public func load() throws -> PersonalData {
        guard FileManager.default.fileExists(atPath: url.path) else { return PersonalData() }
        let result = try JSONDecoder().decode(PersonalData.self, from: Data(contentsOf: url))
        try result.validate(); return result
    }
    public func save(_ data: PersonalData) throws {
        try data.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var updated = data
        if updated.products.contains(where: { $0.unit == .milliliters }) { updated.version = 2 }
        try encoder.encode(updated).write(to: url, options: .atomic)
    }
}
