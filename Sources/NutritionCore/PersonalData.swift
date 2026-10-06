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
        self == .watch ? "Расход в покое + активные калории за выбранный день. Если активность ещё ни разу не вносилась, к покою прибавляется минимальная бытовая активность (×1,2)."
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
    /// Sedentary allowance used until the day's activity arrives, so a missing import
    /// (or no Apple Watch at all) never leaves the target at resting expenditure alone.
    public var provisionalActivity: Double = 0
    public var creditedActivity: Double { creditsActivity ? (active ?? provisionalActivity) : 0 }
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
        // Without any activity history (no Apple Watch), resting expenditure alone is never a whole day's need.
        // Someone who does log activity sees only calories actually burned; a manual base is the user's own choice.
        let provisional = adds && active == nil && manualTarget == nil && activity.isEmpty
            ? (base * (ActivityLevel.low.factor - 1)).rounded() : 0
        let maintenance = base + (adds ? (active ?? provisional) : 0)
        var deficit = 0.0
        // A manually supplied target is already the user's goal. Never subtract a second deficit.
        if settings.goal == .gentleLoss, manualTarget == nil, let profile,
           profile.weight / pow(profile.height / 100, 2) >= 18.5 {
            let floor = profile.sex == .male ? 1500.0 : 1200.0
            deficit = max(0, min(300, maintenance * 0.1, maintenance - floor)).rounded()
        }
        return DayBudget(base: base, active: active, creditsActivity: adds, deficit: deficit, eaten: eaten,
                         provisionalActivity: provisional)
    }
    public func validate() throws {
        guard (1...2).contains(version) else { throw FoodError.storageVersion }
        guard products.allSatisfy(\.isValid), Set(products.map(\.id)).count == products.count,
              profile?.isValid != false,
              manualTarget.map({ $0.isFinite && (500...10_000).contains($0) }) ?? true,
              (dietaryNotes?.count ?? 0) <= 1000,
              activity.allSatisfy(\.isValid), Set(activity.map(\.day)).count == activity.count else { throw PersonalError.invalidData }
    }
    public mutating func mergeActivity(_ incoming: [DailyActivity], preferIncoming: Bool = false) throws {
        guard incoming.allSatisfy(\.isValid), Set(incoming.map(\.day)).count == incoming.count else { throw PersonalError.invalidActivity }
        guard activity.allSatisfy(\.isValid), Set(activity.map(\.day)).count == activity.count else { throw PersonalError.invalidData }
        var byDay = Dictionary(uniqueKeysWithValues: activity.map { ($0.day, $0) })
        for item in incoming {
            if !preferIncoming, let previous = byDay[item.day], previous.updatedAt > item.updatedAt { continue }
            byDay[item.day] = item
        }
        activity = byDay.values.sorted { $0.day > $1.day }
    }
    /// Drops only the parts that fail validation. Used to recover a partly damaged file.
    public mutating func discardInvalid() {
        var ids = Set<UUID>(); products = products.filter { $0.isValid && ids.insert($0.id).inserted }
        var days = Set<String>(); activity = activity.filter { $0.isValid && days.insert($0.day).inserted }
        if profile?.isValid == false { profile = nil }
        if let target = manualTarget, !(target.isFinite && (500...10_000).contains(target)) { manualTarget = nil }
        if let notes = dietaryNotes, notes.count > 1000 { dietaryNotes = String(notes.prefix(1000)) }
    }
    /// Applies only this window's changes on top of what another copy has saved meanwhile.
    /// Activity keeps the newest value per day; any other field edited in both copies is a conflict.
    public static func merge(base: PersonalData, proposed: PersonalData, current: PersonalData) throws -> PersonalData {
        var result = current
        func field<T: Equatable>(_ key: WritableKeyPath<PersonalData, T>) throws {
            guard base[keyPath: key] != proposed[keyPath: key] else { return }
            guard current[keyPath: key] == base[keyPath: key] || current[keyPath: key] == proposed[keyPath: key]
            else { throw PersonalError.storageConflict }
            result[keyPath: key] = proposed[keyPath: key]
        }
        try field(\.profile); try field(\.manualTarget); try field(\.budgetSettings)
        try field(\.linkedFileBookmark); try field(\.linkedFileName)
        try field(\.coachEnabled); try field(\.dietaryNotes)
        if base.products != proposed.products {
            let before = Dictionary(base.products.map { ($0.id, $0) }) { first, _ in first }
            let after = Dictionary(proposed.products.map { ($0.id, $0) }) { first, _ in first }
            var products = Dictionary(current.products.map { ($0.id, $0) }) { first, _ in first }
            for id in Set(before.keys).union(after.keys) where before[id] != after[id] {
                guard products[id] == before[id] || products[id] == after[id] else { throw PersonalError.storageConflict }
                products[id] = after[id]
            }
            result.products = products.values.sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
            }
        }
        if base.activity != proposed.activity {
            let before = Dictionary(base.activity.map { ($0.day, $0) }) { first, _ in first }
            let after = Dictionary(proposed.activity.map { ($0.day, $0) }) { first, _ in first }
            var days = Dictionary(current.activity.map { ($0.day, $0) }) { first, _ in first }
            for day in Set(before.keys).union(after.keys) where before[day] != after[day] {
                guard let incoming = after[day] else {
                    if days[day] == before[day] { days[day] = nil }
                    continue
                }
                if let existing = days[day], existing != before[day], existing.updatedAt > incoming.updatedAt { continue }
                days[day] = incoming
            }
            result.activity = days.values.sorted { $0.day > $1.day }
        }
        result.version = max(current.version, proposed.version)
        return result
    }
}
public enum PersonalError: LocalizedError {
    case invalidData, invalidActivity, noActivity, invalidFormat, storageConflict
    public var errorDescription: String? {
        switch self {
        case .storageConflict: "Продукты, профиль или настройки только что изменены в другой копии «Тарелки». Данные обновлены — повторите действие."
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
    private var lockURL: URL { url.deletingLastPathComponent().appendingPathComponent(".personal.lock") }

    /// A damaged product or activity row never hides the rest. An unreadable or newer file still throws.
    public func load() throws -> PersonalData { try read().data }

    /// Repairs a partly damaged file after keeping its original bytes beside it. Returns the backup.
    public func recoverDamaged() throws -> URL? {
        try PrivateStorage.withExclusiveLock(at: lockURL) {
            let stored = try read()
            guard stored.repaired else { return nil }
            let backup = try keepDamaged(stored.bytes)
            try write(stored.data)
            return backup
        }
    }

    /// With a baseline, merges only the changes made since it was loaded; never overwrites
    /// another copy's edits silently. Returns what was actually stored.
    @discardableResult
    public func save(_ data: PersonalData, replacing baseline: PersonalData? = nil) throws -> PersonalData {
        try data.validate()
        return try PrivateStorage.withExclusiveLock(at: lockURL) {
            var result = data
            if let baseline {
                let stored = try read()
                if stored.repaired { _ = try keepDamaged(stored.bytes) }
                result = try PersonalData.merge(base: baseline, proposed: data, current: stored.data)
                try result.validate()
            } else if let stored = try? read(), stored.repaired {
                _ = try keepDamaged(stored.bytes)
            }
            if result.products.contains(where: { $0.unit == .milliliters }) { result.version = 2 }
            try write(result)
            return result
        }
    }

    private struct Header: Decodable { let version: Int? }

    private func read() throws -> (data: PersonalData, repaired: Bool, bytes: Data) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (PersonalData(), false, Data()) }
        let bytes = try Data(contentsOf: url)
        let header = try JSONDecoder().decode(Header.self, from: bytes)
        guard (1...2).contains(header.version ?? 1) else { throw FoodError.storageVersion }
        if let strict = try? JSONDecoder().decode(PersonalData.self, from: bytes), (try? strict.validate()) != nil {
            return (strict, false, bytes)
        }
        var repaired = try JSONDecoder().decode(LenientPersonalData.self, from: bytes).value
        repaired.discardInvalid()
        try repaired.validate()
        return (repaired, true, bytes)
    }

    private func write(_ data: PersonalData) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateStorage.write(encoder.encode(data), to: url)
    }

    private func keepDamaged(_ bytes: Data) throws -> URL {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("personal-damaged-\(Int(Date().timeIntervalSince1970)).json")
        try PrivateStorage.write(bytes, to: backup)
        return backup
    }
}

/// Decodes whatever is readable, field by field and row by row.
private struct LenientPersonalData: Decodable {
    let value: PersonalData
    private enum Keys: String, CodingKey {
        case version, products, profile, manualTarget, activity, linkedFileBookmark, linkedFileName
        case budgetSettings, coachEnabled, dietaryNotes
    }
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        var data = PersonalData()
        data.version = (try? values.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        data.products = ((try? values.decodeIfPresent([Lossy<SavedProduct>].self, forKey: .products)) ?? [])
            .compactMap(\.value)
        data.activity = ((try? values.decodeIfPresent([Lossy<DailyActivity>].self, forKey: .activity)) ?? [])
            .compactMap(\.value)
        data.profile = try? values.decodeIfPresent(CalorieProfile.self, forKey: .profile)
        data.manualTarget = try? values.decodeIfPresent(Double.self, forKey: .manualTarget)
        data.linkedFileBookmark = try? values.decodeIfPresent(Data.self, forKey: .linkedFileBookmark)
        data.linkedFileName = try? values.decodeIfPresent(String.self, forKey: .linkedFileName)
        data.budgetSettings = try? values.decodeIfPresent(BudgetSettings.self, forKey: .budgetSettings)
        data.coachEnabled = try? values.decodeIfPresent(Bool.self, forKey: .coachEnabled)
        data.dietaryNotes = try? values.decodeIfPresent(String.self, forKey: .dietaryNotes)
        value = data
    }
}
